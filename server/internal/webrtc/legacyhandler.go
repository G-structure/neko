package webrtc

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/m1k1o/neko/server/pkg/types"

	"github.com/rs/zerolog"
)

const (
	OP_MOVE     = 0x01
	OP_SCROLL   = 0x02
	OP_KEY_DOWN = 0x03
	OP_KEY_UP   = 0x04
	OP_KEY_CLK  = 0x05
	// OP_ROBOT carries a JSON robot command (a G1 setpoint/LowCmd), NOT an input
	// event. It is routed to the in-container robot bridge over localhost — never
	// to X11 XTEST — so a robot setpoint sent over the data channel reaches the
	// Isaac extension (where capability is enforced), never a synthetic mouse/key.
	OP_ROBOT = 0x10
)

// robotBridgeClient posts OP_ROBOT payloads to the in-container robot bridge.
// Short timeout + fire-and-forget so a slow or absent bridge never stalls the
// WebRTC data-channel read loop.
var robotBridgeClient = &http.Client{Timeout: 2 * time.Second}

type PayloadHeader struct {
	Event  uint8
	Length uint16
}

type PayloadMove struct {
	PayloadHeader
	X uint16
	Y uint16
}

type PayloadScroll struct {
	PayloadHeader
	X int16
	Y int16
}

type PayloadKey struct {
	PayloadHeader
	Key uint64 // TODO: uint32
}

func (manager *WebRTCManagerCtx) handleLegacy(
	logger zerolog.Logger, data []byte,
	session types.Session,
) error {
	// continue only if session is host
	if !session.LegacyIsHost() {
		return nil
	}

	buffer := bytes.NewBuffer(data)
	header := &PayloadHeader{}
	hbytes := make([]byte, 3)

	if _, err := buffer.Read(hbytes); err != nil {
		return err
	}

	if err := binary.Read(bytes.NewBuffer(hbytes), binary.LittleEndian, header); err != nil {
		return err
	}

	buffer = bytes.NewBuffer(data)

	switch header.Event {
	case OP_MOVE:
		payload := &PayloadMove{}
		if err := binary.Read(buffer, binary.LittleEndian, payload); err != nil {
			return err
		}

		manager.desktop.Move(int(payload.X), int(payload.Y))
	case OP_SCROLL:
		payload := &PayloadScroll{}
		if err := binary.Read(buffer, binary.LittleEndian, payload); err != nil {
			return err
		}

		logger.
			Trace().
			Str("x", strconv.Itoa(int(payload.X))).
			Str("y", strconv.Itoa(int(payload.Y))).
			Msg("scroll")

		manager.desktop.Scroll(int(payload.X), int(payload.Y), false)
	case OP_KEY_DOWN:
		payload := &PayloadKey{}
		if err := binary.Read(buffer, binary.LittleEndian, payload); err != nil {
			return err
		}

		if payload.Key < 8 {
			err := manager.desktop.ButtonDown(uint32(payload.Key))
			if err != nil {
				logger.Warn().Err(err).Msg("button down failed")
				return nil
			}

			logger.Trace().Msgf("button down %d", payload.Key)
		} else {
			err := manager.desktop.KeyDown(uint32(payload.Key))
			if err != nil {
				logger.Warn().Err(err).Msg("key down failed")
				return nil
			}

			logger.Trace().Msgf("key down %d", payload.Key)
		}
	case OP_KEY_UP:
		payload := &PayloadKey{}
		err := binary.Read(buffer, binary.LittleEndian, payload)
		if err != nil {
			return err
		}

		if payload.Key < 8 {
			err := manager.desktop.ButtonUp(uint32(payload.Key))
			if err != nil {
				logger.Warn().Err(err).Msg("button up failed")
				return nil
			}

			logger.Trace().Msgf("button up %d", payload.Key)
		} else {
			err := manager.desktop.KeyUp(uint32(payload.Key))
			if err != nil {
				logger.Warn().Err(err).Msg("key up failed")
				return nil
			}

			logger.Trace().Msgf("key up %d", payload.Key)
		}
	case OP_ROBOT:
		// header.Length is the byte length of the trailing JSON command body.
		// Route it to the robot bridge; a short/oversized frame is a no-op (never
		// a synthetic input event).
		end := 3 + int(header.Length)
		if header.Length == 0 || end > len(data) {
			logger.Warn().Uint16("length", header.Length).Msg("invalid OP_ROBOT frame")
			return nil
		}
		manager.forwardRobotCommand(logger, data[3:end])
	case OP_KEY_CLK:
		// unused
		break
	}

	return nil
}

// forwardRobotCommand relays a data-channel robot command to the in-container
// robot bridge. It NEVER touches X11 XTEST. Capability is enforced downstream at
// the Isaac extension; this only refuses the operator escalation at the edge
// (mirroring the control-plane WS whitelist) and drops anything malformed.
func (manager *WebRTCManagerCtx) forwardRobotCommand(logger zerolog.Logger, body []byte) {
	url := manager.config.RobotBridgeURL
	if url == "" {
		logger.Warn().Msg("OP_ROBOT received but webrtc.robot_bridge_url is not set; dropping")
		return
	}

	var probe struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(body, &probe); err != nil || probe.Type == "" {
		logger.Warn().Msg("OP_ROBOT payload is not a typed JSON command; dropping")
		return
	}
	if probe.Type == "spawn" || probe.Type == "robots.g1.spawn" {
		logger.Warn().Str("type", probe.Type).Msg("OP_ROBOT operator command rejected at edge")
		return
	}

	payload := make([]byte, len(body))
	copy(payload, body)
	go func() {
		req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(payload))
		if err != nil {
			logger.Warn().Err(err).Msg("robot bridge request build failed")
			return
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := robotBridgeClient.Do(req)
		if err != nil {
			logger.Warn().Err(err).Msg("robot bridge post failed")
			return
		}
		_ = resp.Body.Close()
	}()
}
