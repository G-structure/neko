package agent

import (
	"errors"
	"net/http"
	"sync"
	"time"

	"github.com/kataras/go-events"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/m1k1o/neko/server/pkg/types"
)

// SingleSessionManager implements types.SessionManager for single-user agent mode
type SingleSessionManager struct {
	mu       sync.RWMutex
	logger   zerolog.Logger
	session  types.Session
	token    string
	settings types.Settings
	emmiter  events.EventEmmiter

	cursors   map[types.Session][]types.Cursor
	cursorsMu sync.Mutex
}

// NewSingleSessionManager creates a minimal session manager for agent mode
func NewSingleSessionManager(token string) *SingleSessionManager {
	logger := log.With().Str("module", "agent-session").Logger()

	manager := &SingleSessionManager{
		logger:  logger,
		token:   token,
		emmiter: events.New(),
		cursors: make(map[types.Session][]types.Cursor),
		settings: types.Settings{
			PrivateMode:       false,
			LockedLogins:      true,  // No new logins in agent mode
			LockedControls:    false, // Agent always has control
			ControlProtection: false,
			ImplicitHosting:   true,  // Agent is always host
			InactiveCursors:   false,
			MercifulReconnect: true,
			HeartbeatInterval: 10,
		},
	}

	// Create the single agent session
	profile := types.MemberProfile{
		Name:               "Agent",
		IsAdmin:            true,
		CanLogin:           true,
		CanConnect:         true,
		CanWatch:           true,
		CanHost:            true,
		CanAccessClipboard: true,
	}

	session := &SingleSession{
		id:      "agent",
		token:   token,
		manager: manager,
		logger:  logger.With().Str("session_id", "agent").Logger(),
		profile: profile,
	}

	manager.session = session

	return manager
}

// Create returns error - not supported in agent mode
func (m *SingleSessionManager) Create(id string, profile types.MemberProfile) (types.Session, string, error) {
	return nil, "", errors.New("session creation not supported in agent mode")
}

// Update returns error - not supported in agent mode
func (m *SingleSessionManager) Update(id string, profile types.MemberProfile) error {
	return errors.New("session update not supported in agent mode")
}

// Delete returns error - not supported in agent mode
func (m *SingleSessionManager) Delete(id string) error {
	return errors.New("session deletion not supported in agent mode")
}

// Disconnect does nothing in agent mode
func (m *SingleSessionManager) Disconnect(id string) error {
	if id != "agent" {
		return types.ErrSessionNotFound
	}
	// Don't actually disconnect the agent session
	return nil
}

// Get returns the single agent session
func (m *SingleSessionManager) Get(id string) (types.Session, bool) {
	if id == "agent" {
		return m.session, true
	}
	return nil, false
}

// GetByToken validates token and returns agent session
func (m *SingleSessionManager) GetByToken(token string) (types.Session, bool) {
	if token == m.token {
		return m.session, true
	}
	return nil, false
}

// List returns array with single agent session
func (m *SingleSessionManager) List() []types.Session {
	return []types.Session{m.session}
}

// Range iterates over the single session
func (m *SingleSessionManager) Range(f func(types.Session) bool) {
	f(m.session)
}

// GetHost always returns the agent session as host
func (m *SingleSessionManager) GetHost() (types.Session, bool) {
	return m.session, true
}

// SetCursor stores cursor position
func (m *SingleSessionManager) SetCursor(cursor types.Cursor, session types.Session) {
	m.cursorsMu.Lock()
	defer m.cursorsMu.Unlock()

	list := m.cursors[session]
	list = append(list, cursor)
	m.cursors[session] = list
}

// PopCursors returns and clears stored cursors
func (m *SingleSessionManager) PopCursors() map[types.Session][]types.Cursor {
	m.cursorsMu.Lock()
	defer m.cursorsMu.Unlock()

	cursors := m.cursors
	m.cursors = make(map[types.Session][]types.Cursor)
	return cursors
}

// Broadcast sends event to the single session if connected
func (m *SingleSessionManager) Broadcast(event string, payload any, exclude ...string) {
	if m.session.State().IsConnected {
		// Check if session is excluded
		for _, ex := range exclude {
			if ex == "agent" {
				return
			}
		}
		m.session.Send(event, payload)
	}
}

// AdminBroadcast same as Broadcast in agent mode (agent is admin)
func (m *SingleSessionManager) AdminBroadcast(event string, payload any, exclude ...string) {
	m.Broadcast(event, payload, exclude...)
}

// InactiveCursorsBroadcast not used in agent mode
func (m *SingleSessionManager) InactiveCursorsBroadcast(event string, payload any, exclude ...string) {
	// Not implemented in agent mode
}

// Event listeners
func (m *SingleSessionManager) OnCreated(listener func(session types.Session)) {
	m.emmiter.On("created", func(payload ...any) {
		listener(payload[0].(types.Session))
	})
}

func (m *SingleSessionManager) OnDeleted(listener func(session types.Session)) {
	m.emmiter.On("deleted", func(payload ...any) {
		listener(payload[0].(types.Session))
	})
}

func (m *SingleSessionManager) OnConnected(listener func(session types.Session)) {
	m.emmiter.On("connected", func(payload ...any) {
		listener(payload[0].(types.Session))
	})
}

func (m *SingleSessionManager) OnDisconnected(listener func(session types.Session)) {
	m.emmiter.On("disconnected", func(payload ...any) {
		listener(payload[0].(types.Session))
	})
}

func (m *SingleSessionManager) OnProfileChanged(listener func(session types.Session, new, old types.MemberProfile)) {
	m.emmiter.On("profile_changed", func(payload ...any) {
		listener(payload[0].(types.Session), payload[1].(types.MemberProfile), payload[2].(types.MemberProfile))
	})
}

func (m *SingleSessionManager) OnStateChanged(listener func(session types.Session)) {
	m.emmiter.On("state_changed", func(payload ...any) {
		listener(payload[0].(types.Session))
	})
}

func (m *SingleSessionManager) OnHostChanged(listener func(session, host types.Session)) {
	m.emmiter.On("host_changed", func(payload ...any) {
		if payload[1] == nil {
			listener(payload[0].(types.Session), nil)
		} else {
			listener(payload[0].(types.Session), payload[1].(types.Session))
		}
	})
}

func (m *SingleSessionManager) OnSettingsChanged(listener func(session types.Session, new, old types.Settings)) {
	m.emmiter.On("settings_changed", func(payload ...any) {
		listener(payload[0].(types.Session), payload[1].(types.Settings), payload[2].(types.Settings))
	})
}

// UpdateSettingsFunc updates settings (minimal support)
func (m *SingleSessionManager) UpdateSettingsFunc(session types.Session, f func(settings *types.Settings) bool) {
	m.mu.Lock()
	new := m.settings
	if f(&new) {
		old := m.settings
		m.settings = new
		m.mu.Unlock()
		m.emmiter.Emit("settings_changed", session, new, old)
		return
	}
	m.mu.Unlock()
}

// Settings returns current settings
func (m *SingleSessionManager) Settings() types.Settings {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.settings
}

// CookieEnabled returns false - no cookies in agent mode
func (m *SingleSessionManager) CookieEnabled() bool {
	return false
}

// Stats returns minimal stats
func (m *SingleSessionManager) Stats() types.Stats {
	return types.Stats{
		HasHost:         true,
		HostId:          "agent",
		ServerStartedAt: time.Now(),
		TotalUsers:      1,
		LastUserLeftAt:  nil,
		TotalAdmins:     1,
		LastAdminLeftAt: nil,
	}
}

// CookieSetToken not used in agent mode
func (m *SingleSessionManager) CookieSetToken(w http.ResponseWriter, token string) {
	// Not implemented in agent mode
}

// CookieClearToken not used in agent mode
func (m *SingleSessionManager) CookieClearToken(w http.ResponseWriter, r *http.Request) {
	// Not implemented in agent mode
}

// Authenticate validates token from request
func (m *SingleSessionManager) Authenticate(r *http.Request) (types.Session, error) {
	// Check Authorization header
	token := r.Header.Get("Authorization")
	if token == "" {
		// Check query parameter
		token = r.URL.Query().Get("token")
	}
	if token == "" {
		// Check password parameter (for compatibility)
		token = r.URL.Query().Get("password")
	}

	if token == m.token {
		return m.session, nil
	}

	return nil, errors.New("invalid token")
}

// SingleSession implements types.Session for the agent
type SingleSession struct {
	mu      sync.RWMutex
	id      string
	token   string
	manager *SingleSessionManager
	logger  zerolog.Logger
	profile types.MemberProfile
	state   types.SessionState

	websocketPeer types.WebSocketPeer
	webrtcPeer    types.WebRTCPeer
}

func (s *SingleSession) ID() string {
	return s.id
}

func (s *SingleSession) Profile() types.MemberProfile {
	return s.profile
}

func (s *SingleSession) State() types.SessionState {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.state
}

func (s *SingleSession) IsHost() bool {
	return true // Agent is always host
}

func (s *SingleSession) LegacyIsHost() bool {
	return true // Agent is always host
}

func (s *SingleSession) SetAsHost() {
	// No-op, agent is always host
}

func (s *SingleSession) SetAsHostBy(session types.Session) {
	// No-op, agent is always host
}

func (s *SingleSession) ClearHost() {
	// No-op, agent is always host
}

func (s *SingleSession) PrivateModeEnabled() bool {
	return false // No private mode in agent
}

func (s *SingleSession) SetCursor(cursor types.Cursor) {
	s.manager.SetCursor(cursor, s)
}

func (s *SingleSession) ConnectWebSocketPeer(websocketPeer types.WebSocketPeer) {
	s.mu.Lock()
	s.websocketPeer = websocketPeer
	s.state.IsConnected = true
	now := time.Now()
	s.state.ConnectedSince = &now
	s.mu.Unlock()

	s.manager.emmiter.Emit("connected", s)
	s.manager.emmiter.Emit("state_changed", s)
}

func (s *SingleSession) DisconnectWebSocketPeer(websocketPeer types.WebSocketPeer, delayed bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.websocketPeer != websocketPeer {
		return
	}

	if delayed {
		// In agent mode, we might want to wait for reconnection
		go func() {
			time.Sleep(5 * time.Second)
			s.mu.Lock()
			defer s.mu.Unlock()
			if s.websocketPeer == websocketPeer {
				s.disconnectNow()
			}
		}()
	} else {
		s.disconnectNow()
	}
}

func (s *SingleSession) disconnectNow() {
	s.websocketPeer = nil
	s.state.IsConnected = false
	now := time.Now()
	s.state.NotConnectedSince = &now
	s.state.ConnectedSince = nil

	s.manager.emmiter.Emit("disconnected", s)
	s.manager.emmiter.Emit("state_changed", s)
}

func (s *SingleSession) DestroyWebSocketPeer(reason string) {
	s.mu.Lock()
	if s.websocketPeer != nil {
		s.websocketPeer.Destroy(reason)
		s.websocketPeer = nil
	}
	s.state.IsConnected = false
	now := time.Now()
	s.state.NotConnectedSince = &now
	s.state.ConnectedSince = nil
	s.mu.Unlock()

	s.manager.emmiter.Emit("disconnected", s)
	s.manager.emmiter.Emit("state_changed", s)
}

func (s *SingleSession) Send(event string, payload any) {
	s.mu.RLock()
	peer := s.websocketPeer
	s.mu.RUnlock()

	if peer != nil {
		peer.Send(event, payload)
	}
}

func (s *SingleSession) SetWebRTCPeer(webrtcPeer types.WebRTCPeer) {
	s.mu.Lock()
	s.webrtcPeer = webrtcPeer
	s.mu.Unlock()
}

func (s *SingleSession) SetWebRTCConnected(webrtcPeer types.WebRTCPeer, connected bool) {
	s.mu.Lock()
	if s.webrtcPeer == webrtcPeer {
		s.state.IsWatching = connected
		now := time.Now()
		if connected {
			s.state.WatchingSince = &now
			s.state.NotWatchingSince = nil
		} else {
			s.state.NotWatchingSince = &now
			s.state.WatchingSince = nil
		}
	}
	s.mu.Unlock()

	s.manager.emmiter.Emit("state_changed", s)
}

func (s *SingleSession) GetWebRTCPeer() types.WebRTCPeer {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.webrtcPeer
}