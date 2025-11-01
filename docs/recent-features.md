# Recent Features and Improvements

This document summarizes the major features added in the recent development cycle (commits `60b49ba1` and `3f33ce46`).

## Table of Contents

1. [Agent Mode](#agent-mode)
2. [macOS Support](#macos-support)
3. [Platform Abstraction Layer](#platform-abstraction-layer)
4. [Architecture Changes](#architecture-changes)

---

## Agent Mode

### Overview

Agent mode is a minimal, single-user version of Neko designed for personal desktop streaming without the complexity of multi-user management.

**Key Features:**
- Single pre-authenticated session (no login flow)
- Token-based authentication only
- Minimal resource footprint
- Compatible with existing Neko clients
- Systemd service integration for Linux

**Introduced in:** Commit `60b49ba14325ca6662f35e1c1dbc350c8e46c1f3`

### New Components

#### Command Implementation
- **File:** `server/cmd/agent.go`
- **Purpose:** New `neko agent` subcommand
- **Features:**
  - Automatic token generation if not provided
  - Reuses core Neko managers (desktop, capture, webrtc)
  - Simplified configuration
  - Single session manager instead of full member system

#### Session Manager
- **File:** `server/internal/agent/session.go`
- **Purpose:** Single-session replacement for multi-user session management
- **Features:**
  - Single hardcoded session with admin privileges
  - No member management overhead
  - Automatic host assignment
  - Compatible with WebSocket protocol

#### API Manager
- **File:** `server/internal/agent/api.go`
- **Purpose:** Minimal HTTP API for agent mode
- **Endpoints:**
  - `GET /health` - Health check
  - `GET /stats` - System statistics
  - `WS /api/ws` - WebSocket connection (main protocol)

### Usage Differences

| Feature | Full Neko | Agent Mode |
|---------|-----------|------------|
| Multi-user support | ✅ Full | ❌ Single user |
| Authentication | Username/Password | Token only |
| Session management | Full CRUD API | Single fixed session |
| Admin controls | Role-based | Always admin |
| Plugins | Supported | Disabled |
| API surface | Full REST API | Health + Stats only |
| Resource usage | Higher | Minimal |

### Installation & Deployment

**Automated Installation (Linux):**
```bash
./scripts/install-agent.sh
```

**Manual Usage:**
```bash
# Generate secure token
TOKEN=$(openssl rand -hex 32)

# Run agent
./neko agent --token=$TOKEN --desktop.display=:0 --server.bind=0.0.0.0:8080
```

**Systemd Service:**
```bash
# Install service
sudo cp scripts/neko-agent.service /etc/systemd/system/neko-agent@.service

# Start and enable
sudo systemctl start neko-agent@$USER
sudo systemctl enable neko-agent@$USER
```

**Related Files:**
- `AGENT.md` - Full agent mode documentation
- `scripts/install-agent.sh` - Automated installation script
- `scripts/neko-agent.service` - Systemd service template
- `scripts/agent-config.yaml` - Default configuration

---

## macOS Support

### Overview

Full macOS support enables Neko to run natively on macOS without requiring X11 or virtualization. This implementation uses native macOS APIs for screen capture, input control, and audio.

**Introduced in:** Commit `3f33ce4687cdecea2f83bf4198c3fe24224cb2ac`

### Key Capabilities

#### Screen Capture
- **Technology:** AVFoundation (`avfvideosrc`)
- **Features:**
  - Native screen capture without X11
  - Built-in cursor capture
  - Full Retina display support
  - Primary display capture

**GStreamer Pipeline:**
```gstreamer
avfvideosrc capture-screen=true capture-screen-cursor=true !
  video/x-raw,framerate=30/1 !
  videoconvert !
  x264enc tune=zerolatency !
  appsink
```

#### Audio Capture
- **Technology:** Core Audio (`osxaudiosrc`)
- **Features:**
  - System audio capture
  - Microphone input support
  - Native audio device integration

#### Input Control
- **Technology:** CGEvent API via RobotGo
- **Features:**
  - Full mouse control (move, click, scroll)
  - Keyboard input with platform keycode mapping
  - Clipboard integration
  - System pasteboard support

### New Components

#### Darwin Backend
- **File:** `server/pkg/darwin/darwin.go`
- **Purpose:** macOS-specific desktop operations implementation
- **Key Methods:**
  - `Init()` - Initialize RobotGo backend
  - `Move()`, `ButtonDown()`, `ButtonUp()` - Mouse control
  - `KeyDown()`, `KeyUp()` - Keyboard control
  - `GetScreenSize()`, `TakeScreenshot()` - Screen operations
  - `SetClipboard()`, `GetClipboard()` - Clipboard operations

#### Keycode Mapping
- **File:** `server/pkg/darwin/keymap.go`
- **Purpose:** X11 keycode to macOS keycode translation
- **Coverage:** Complete keyboard mapping including:
  - Standard alphanumeric keys
  - Function keys (F1-F24)
  - Modifier keys (Shift, Control, Alt/Option, Command)
  - Special keys (arrows, delete, home, end, page up/down)

#### Cursor Capture
- **File:** `server/pkg/darwin/cursor.go`
- **Purpose:** NSCursor API integration for cursor image extraction
- **Features:**
  - RGBA bitmap extraction
  - Hotspot coordinate detection
  - Compatible with VNC cursor pseudo-encoding

**Implementation Details:**
```objective-c
// Uses NSCursor.currentSystemCursor
// Extracts CGImage and converts to RGBA
// Returns cursor image with hotspot coordinates
```

### macOS Permissions Required

The agent requires two critical system permissions:

1. **Screen Recording Permission**
   - **Location:** System Settings → Privacy & Security → Screen Recording
   - **Purpose:** Capture screen content
   - **When:** First run triggers system prompt

2. **Accessibility Permission**
   - **Location:** System Settings → Privacy & Security → Accessibility
   - **Purpose:** Control mouse and keyboard via CGEvent
   - **When:** First run triggers system prompt

**Important:** Agent must be restarted after granting permissions.

### Installation

**Prerequisites:**
```bash
# Install GStreamer
brew install gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly

# Install Go
brew install go
```

**Build from Source:**
```bash
cd server
go mod download
CGO_ENABLED=1 go build -tags darwin -o bin/neko ./cmd/neko
```

**Automated Installation:**
```bash
./scripts/install-agent-macos.sh
```

**LaunchAgent Setup:**
```bash
# Start on login
launchctl load ~/Library/LaunchAgents/com.neko.agent.plist

# View logs
tail -f ~/Library/Logs/neko-agent.log
```

**Related Files:**
- `MACOS.md` - Comprehensive macOS documentation
- `MACOS_QUICKSTART.md` - Quick start guide
- `MACOS_CURSOR_CAPTURE.md` - Cursor capture research and implementation
- `scripts/install-agent-macos.sh` - macOS installation script
- `server/install-gstreamer-and-build.sh` - Build helper script

---

## Platform Abstraction Layer

### Overview

A new platform-agnostic interface was introduced to support multiple desktop backends (X11, macOS, and potentially Windows in the future).

### Backend Interface

**File:** `server/pkg/desktop/backend.go`

**Purpose:** Define common interface for all platform-specific desktop operations.

**Interface Methods:**

```go
type Backend interface {
    // Initialization
    Init(display string) error
    Shutdown()

    // Screen operations
    GetScreenSize() types.ScreenSize
    SetScreenSize(size types.ScreenSize) (types.ScreenSize, error)
    GetScreenConfigurations() map[int]ScreenConfiguration
    TakeScreenshot() (image.Image, error)

    // Mouse operations
    Move(x, y int)
    GetCursorPosition() (int, int)
    Scroll(deltaX, deltaY int, controlKey bool)
    ButtonDown(code uint32) error
    ButtonUp(code uint32) error

    // Keyboard operations
    KeyDown(code uint32) error
    KeyUp(code uint32) error
    ResetKeys()
    SetKeyboardModifier(mod uint8, active bool)
    GetKeyboardModifiers() uint8
    KeyPress(codes ...uint32) error

    // Clipboard operations
    SetClipboard(text string)
    GetClipboard() (string, error)
}
```

### Backend Implementations

#### Xorg Backend (Linux)
- **File:** `server/pkg/xorg/backend.go`
- **Technology:** X11 libraries (libX11, libXrandr, libXtst)
- **Purpose:** Refactored from original `xorg.go` to implement Backend interface
- **Features:**
  - X11 display connection
  - XRandR for screen resolution management
  - XTest for input injection
  - X11 clipboard support

#### Darwin Backend (macOS)
- **File:** `server/pkg/darwin/darwin.go`
- **Technology:** RobotGo (wraps CGEvent and NSCursor APIs)
- **Purpose:** Native macOS desktop operations
- **Features:**
  - CoreGraphics event posting
  - NSScreen for display information
  - NSPasteboard for clipboard
  - Read-only screen size (no dynamic resolution changes)

#### Stub Implementations
For cross-compilation and platforms without full support:
- `server/pkg/darwin/darwin_stub.go` - Stub for non-macOS builds
- `server/pkg/xorg/xorg_stub.go` - Stub for non-Linux builds

### Build Tags

Platform-specific code uses Go build tags:

```go
// +build darwin
package darwin

// +build linux
package xorg
```

**Build Examples:**
```bash
# macOS build
CGO_ENABLED=1 go build -tags darwin

# Linux build
CGO_ENABLED=1 go build -tags linux
```

---

## Architecture Changes

### Desktop Manager Refactoring

**File:** `server/internal/desktop/manager.go`

**Changes:**
- Factory pattern for backend selection
- Runtime OS detection (`runtime.GOOS`)
- Platform-agnostic API surface
- Backend lifecycle management

**Backend Selection Logic:**
```go
func NewDesktopManagerCtx(config *config.Desktop) *DesktopManagerCtx {
    var backend desktop.Backend

    if runtime.GOOS == "darwin" {
        backend = &darwin.DarwinBackend{}
    } else {
        backend = &xorg.XorgBackend{}
    }

    backend.Init(config.Display)
    return &DesktopManagerCtx{backend: backend}
}
```

### Capture Manager Updates

**File:** `server/internal/capture/manager.go`

**Changes:**
- Platform-specific GStreamer pipeline selection
- macOS: `avfvideosrc` + `osxaudiosrc`
- Linux: `ximagesrc` + `pulsesrc`
- Conditional cursor capture based on platform capabilities

**Pipeline Selection:**
```go
if runtime.GOOS == "darwin" {
    captureSource = fmt.Sprintf(
        "avfvideosrc capture-screen=true capture-screen-cursor=%v ",
        pipelineConf.ShowPointer,
    )
    audioSource = "osxaudiosrc"
} else {
    captureSource = fmt.Sprintf(
        "ximagesrc display-name=%s show-pointer=%v use-damage=false ",
        config.Display, pipelineConf.ShowPointer,
    )
    audioSource = "pulsesrc"
}
```

### Platform-Specific C Code Organization

To support cross-platform builds, C/header files were renamed with platform suffixes:

**Before:**
- `server/pkg/xorg/xorg.c`
- `server/pkg/xorg/xorg.h`
- `server/pkg/drop/drop.c`
- `server/pkg/xevent/xevent.c`

**After:**
- `server/pkg/xorg/xorg_linux.c` (Linux-only)
- `server/pkg/xorg/xorg_linux.h`
- `server/pkg/drop/drop_linux.c` (Linux-only)
- `server/pkg/xevent/xevent_linux.c` (Linux-only)

**Stub files added:**
- `server/pkg/xorg/xorg_stub.go` - For non-Linux builds
- `server/pkg/drop/drop_stub.go` - For non-Linux builds
- `server/pkg/xevent/xevent_stub.go` - For non-Linux builds

### Dependencies Added

**macOS Support (server/go.mod):**
```go
require (
    github.com/go-vgo/robotgo v0.110.4  // macOS input/screen control
)
```

---

## Platform Comparison

### Feature Matrix

| Feature | Linux (X11) | macOS (Darwin) | Windows |
|---------|-------------|----------------|---------|
| Screen Capture | ✅ ximagesrc | ✅ avfvideosrc | ❌ |
| Audio Capture | ✅ PulseAudio | ✅ Core Audio | ❌ |
| Mouse Control | ✅ XTest | ✅ CGEvent | ❌ |
| Keyboard Control | ✅ XTest | ✅ CGEvent | ❌ |
| Cursor Image | ✅ XFixes | ✅ NSCursor | ❌ |
| Screen Resolution | ✅ Changeable | ⚠️ Read-only | ❌ |
| Multiple Displays | ✅ Supported | ⚠️ Primary only | ❌ |
| Clipboard | ✅ X11 | ✅ Pasteboard | ❌ |
| Permissions | ❌ Not required | ✅ Required | ❌ |

**Legend:**
- ✅ Fully supported
- ⚠️ Partial support / limitations
- ❌ Not implemented

### Technology Stack by Platform

**Linux:**
- Display Server: X11
- Screen Capture: GStreamer ximagesrc
- Audio: PulseAudio (pulsesrc)
- Input Control: X11 XTest extension
- Cursor: XFixes extension
- Clipboard: X11 clipboard APIs

**macOS:**
- Display Server: Quartz (Native)
- Screen Capture: AVFoundation (avfvideosrc)
- Audio: Core Audio (osxaudiosrc)
- Input Control: CGEvent API (via RobotGo)
- Cursor: NSCursor API
- Clipboard: NSPasteboard API

---

## Testing the New Features

### Testing Agent Mode (Linux)

```bash
# Build
cd server && ./build core

# Run agent
TOKEN=$(openssl rand -hex 32)
./bin/neko agent --token=$TOKEN

# Connect from client
# URL: ws://localhost:8080/api/ws
# Password: <your token>
```

### Testing macOS Support

```bash
# Install dependencies
brew install gstreamer gst-plugins-{base,good,bad,ugly}

# Build with Darwin support
cd server
CGO_ENABLED=1 go build -tags darwin -o bin/neko ./cmd/neko

# Run agent (after granting permissions)
./bin/neko agent --token=test123

# Expected permissions prompts:
# 1. Screen Recording
# 2. Accessibility
```

### Verifying Platform Abstraction

```bash
# Linux build should use Xorg backend
go build -tags linux

# macOS build should use Darwin backend
go build -tags darwin

# Cross-platform stub should compile without CGO
CGO_ENABLED=0 go build
```

---

## Migration Notes

### For Existing Deployments

**No breaking changes** - existing Docker-based deployments continue to work:
- Docker images still use X11 (Linux) backend
- No configuration changes required
- Agent mode is optional, `neko serve` unchanged

### For Developers

**Backend interface changes:**
- Old `xorg` package functions moved to `xorg.Backend` type
- Desktop manager now wraps backend interface
- Platform detection automatic via `runtime.GOOS`

**Build tag requirements:**
- macOS builds require `-tags darwin`
- Linux builds require `-tags linux`
- Stub builds work without tags (no-op implementations)

---

## Known Limitations

### Agent Mode
- Single user only (by design)
- No plugin support
- Minimal API surface
- No admin/member management features

### macOS Support
- Cannot programmatically change screen resolution
- Primary display only (no multi-monitor selection)
- Requires manual permission grants
- No virtual display creation
- Higher CPU usage than native screen sharing

### Platform Abstraction
- Windows backend not yet implemented
- Wayland support not available
- Some platform-specific features not abstracted (e.g., screen resolution changes)

---

## Future Roadmap

### Agent Mode
- [ ] Windows support via platform abstraction
- [ ] Optional TLS/HTTPS support
- [ ] Built-in TURN server for NAT traversal
- [ ] Configuration hot-reload
- [ ] Metrics/monitoring endpoints

### macOS Support
- [ ] ScreenCaptureKit integration (macOS 12.3+)
- [ ] Hardware-accelerated encoding (VideoToolbox)
- [ ] Multi-display support
- [ ] Virtual display creation
- [ ] Automatic permission detection
- [ ] Touch Bar support for MacBooks

### Platform Abstraction
- [ ] Windows backend (via Windows APIs)
- [ ] Wayland backend (Linux)
- [ ] FreeBSD support
- [ ] Remote desktop protocol abstraction (VNC, RDP backends)

---

## References

### Documentation
- [AGENT.md](../AGENT.md) - Agent mode documentation
- [MACOS.md](../MACOS.md) - macOS support documentation
- [MACOS_QUICKSTART.md](../MACOS_QUICKSTART.md) - macOS quick start
- [MACOS_CURSOR_CAPTURE.md](../MACOS_CURSOR_CAPTURE.md) - Cursor capture implementation guide

### Code Locations
- Agent: `server/cmd/agent.go`, `server/internal/agent/`
- Darwin Backend: `server/pkg/darwin/`
- Xorg Backend: `server/pkg/xorg/`
- Backend Interface: `server/pkg/desktop/backend.go`
- Desktop Manager: `server/internal/desktop/manager.go`
- Capture Manager: `server/internal/capture/manager.go`

### Commits
- Agent Mode: `60b49ba14325ca6662f35e1c1dbc350c8e46c1f3`
- macOS Support: `3f33ce4687cdecea2f83bf4198c3fe24224cb2ac`
