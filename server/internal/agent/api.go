package agent

import (
	"encoding/json"
	"net/http"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/m1k1o/neko/server/pkg/types"
	"github.com/m1k1o/neko/server/pkg/types/codec"
)

// ApiManagerCtx implements types.ApiManager with minimal endpoints for agent mode
type ApiManagerCtx struct {
	logger   zerolog.Logger
	sessions types.SessionManager
	desktop  types.DesktopManager
	capture  types.CaptureManager
}

// NewApiManager creates minimal API manager for agent mode
func NewApiManager(
	sessions types.SessionManager,
	desktop types.DesktopManager,
	capture types.CaptureManager,
) *ApiManagerCtx {
	return &ApiManagerCtx{
		logger:   log.With().Str("module", "agent-api").Logger(),
		sessions: sessions,
		desktop:  desktop,
		capture:  capture,
	}
}

// Route registers minimal API endpoints
func (a *ApiManagerCtx) Route(r types.Router) {
	// Health check endpoint
	r.Get("/health", a.healthCheck)

	// Basic stats endpoint
	r.Get("/stats", a.statsHandler)

	// Screen info endpoint
	r.Get("/screen", a.screenHandler)

	// Minimal room info for client compatibility
	r.Get("/room", a.roomHandler)
}

// AddRouter allows plugins to add custom routes
func (a *ApiManagerCtx) AddRouter(path string, router func(types.Router)) {
	// No-op for agent mode - plugins not supported
}

func (a *ApiManagerCtx) healthCheck(w http.ResponseWriter, r *http.Request) error {
	w.Header().Set("Content-Type", "application/json")
	return json.NewEncoder(w).Encode(map[string]bool{
		"healthy": true,
	})
}

func (a *ApiManagerCtx) statsHandler(w http.ResponseWriter, r *http.Request) error {
	stats := a.sessions.Stats()

	// Add desktop and capture stats
	response := map[string]any{
		"sessions": stats,
		"screen": map[string]any{
			"width":  a.desktop.GetScreenSize().Width,
			"height": a.desktop.GetScreenSize().Height,
			"rate":   a.desktop.GetScreenSize().Rate,
		},
		"capture": map[string]any{
			"video_codec": a.capture.Video().Codec().Name,
			"audio_codec": a.capture.Audio().Codec().Name,
			"broadcast":   a.capture.Broadcast().Started(),
			"screencast":  a.capture.Screencast().Enabled(),
		},
	}

	w.Header().Set("Content-Type", "application/json")
	return json.NewEncoder(w).Encode(response)
}

func (a *ApiManagerCtx) screenHandler(w http.ResponseWriter, r *http.Request) error {
	size := a.desktop.GetScreenSize()

	response := map[string]any{
		"configurations": []types.ScreenSize{size},
		"current": map[string]any{
			"width":  size.Width,
			"height": size.Height,
			"rate":   size.Rate,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	return json.NewEncoder(w).Encode(response)
}

func (a *ApiManagerCtx) roomHandler(w http.ResponseWriter, r *http.Request) error {
	// Minimal room info for client compatibility
	settings := a.sessions.Settings()
	videoCodec := a.capture.Video().Codec()

	response := map[string]any{
		"name": "Agent Desktop",
		"screen": map[string]any{
			"configurations": []types.ScreenSize{a.desktop.GetScreenSize()},
		},
		"settings": settings,
		"video_codec": map[string]any{
			"name": videoCodec.Name,
			"hwenc": videoCodec.Name == codec.VP8().Name ||
			        videoCodec.Name == codec.VP9().Name ||
			        videoCodec.Name == codec.H264().Name,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	return json.NewEncoder(w).Encode(response)
}