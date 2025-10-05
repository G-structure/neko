# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Neko is a self-hosted virtual browser/desktop streaming platform that runs in Docker and uses WebRTC technology. It allows multiple users to access and control applications (browsers, desktops, VLC, etc.) simultaneously through a web interface, with real-time synchronization.

## Architecture

This is a **monorepo** with the following key components:

### Server (Go)
- **Location**: `server/`
- **Language**: Go 1.24+
- **Main packages**:
  - `server/cmd/`: CLI commands (`serve`, `plugins`)
  - `server/internal/`: Core modules (api, capture, config, desktop, http, member, plugins, session, webrtc, websocket)
  - `server/pkg/`: Reusable packages (xorg, xinput, xevent, gst, utils, types, auth, drop)
- **Entry point**: `cmd/neko/main.go`
- **Key dependencies**: Pion WebRTC, Cobra (CLI), Viper (config), Zerolog (logging), GStreamer (video), X11 libraries

### Client (Vue.js 2)
- **Location**: `client/`
- **Language**: TypeScript with Vue.js 2.7
- **Main structure**:
  - `client/src/neko/`: Core WebRTC/WebSocket client logic (base.ts, index.ts, messages.ts, events.ts)
  - `client/src/components/`: UI components
  - `client/src/store/`: Vuex state management
  - `client/src/locale/`: i18n translations
- **Key dependencies**: Vue 2.7, Vuex, WebRTC APIs, Axios, TypeScript

### Runtime (Docker)
- **Location**: `runtime/`
- **Contains**: Xorg configuration, PulseAudio setup, Supervisord configs, Dockerfiles for different flavors (base, intel, nvidia, bookworm)
- **Flavors**: Standard, Intel (hardware acceleration), Nvidia (GPU acceleration)

### Applications
- **Location**: `apps/`
- **Each app** (firefox, chromium, chrome, tor-browser, vlc, xfce, kde, etc.) has its own Dockerfile extending the base image
- **Flavor-specific**: Apps can have `Dockerfile.<flavor>` for specialized builds

## Common Commands

### Building

**Server** (requires Go 1.24+, GStreamer, X11 libs):
```bash
cd server
./build              # Build server + plugins
./build core         # Build server only (skip plugins)
```
Binary output: `server/bin/neko`

**Client** (requires Node.js, npm):
```bash
cd client
npm install
npm run build        # Production build
npm run build:lib    # Build as library
npm run serve        # Development server
```

**Docker images** (using root `./build` script):
```bash
# Build base image
./build --tag latest

# Build specific app
./build --application firefox --tag latest

# Build with flavor
./build --flavor nvidia --application firefox --tag latest

# Full image name (parses automatically)
./build ghcr.io/m1k1o/neko/nvidia-firefox:latest
```

### Testing & Linting

**Client**:
```bash
cd client
npm run lint         # ESLint + Prettier
```

**Server**: No explicit test command in package.json/Makefile. Use standard Go testing:
```bash
cd server
go test ./...
```

### Development

**Run locally with Docker Compose**:
```bash
docker-compose up
```
Exposes:
- Port 8080: HTTP/WebSocket
- Ports 52000-52100/udp: WebRTC

**Environment variables** (see `config.yml` for defaults):
- `NEKO_DESKTOP_SCREEN`: Screen resolution (e.g., 1920x1080@30)
- `NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD`: Admin password
- `NEKO_MEMBER_MULTIUSER_USER_PASSWORD`: User password
- `NEKO_WEBRTC_EPR`: WebRTC port range
- `NEKO_WEBRTC_ICELITE`: Enable ICE Lite mode

## Key Design Patterns

### Server Architecture
- **Modular structure**: Each internal module (webrtc, websocket, desktop, capture, etc.) is self-contained
- **Event-driven**: Uses `github.com/kataras/go-events` for internal event bus
- **Configuration**: Viper-based config with YAML files and environment variables (prefix: `NEKO_`)
- **Plugin system**: Dynamic loading via Go plugins (`server/plugins/`, built as `.so` files)
- **Pion WebRTC**: Custom WebRTC implementation for peer connections and media streaming

### Client Architecture
- **Base client pattern**: `BaseClient` in `client/src/neko/base.ts` handles WebSocket/WebRTC connection
- **Extended client**: `NekoClient` extends BaseClient with Neko-specific logic
- **Message protocol**: Binary WebSocket messages with defined types in `messages.ts`
- **Event system**: EventEmitter3 for client-side events (see `client/src/neko/events.ts`)
- **Vuex store**: Centralized state management with typed-vuex
- **WebRTC flow**: Signaling via WebSocket → SDP exchange → ICE candidates → Media streams

### Docker Build System
- **Template-based**: `Dockerfile.tmpl` processed by `utils/docker/main.go` to generate base images
- **Multi-stage builds**: Runtime Dockerfiles copy compiled server binary and client dist
- **Flavor variants**: Different base images for standard/intel/nvidia hardware acceleration
- **Supervisord**: Manages multiple processes (Xorg, PulseAudio, neko server, target app)

## Configuration Files

- `config.yml`: Default server configuration (desktop, member, session settings)
- `docker-compose.yaml`: Example deployment setup
- `runtime/xorg.conf`: X server configuration
- `runtime/supervisord.conf`: Process management
- `runtime/default.pa`: PulseAudio configuration

## Important Notes

- **WebRTC signaling**: Server acts as signaling server; client initiates SDP offers
- **X11 integration**: Server uses Xorg libraries (libX11, libXrandr, libXtst) for desktop control
- **Video pipeline**: GStreamer for encoding/decoding (H264, VP8, VP9, AV1)
- **Multi-user**: Session management with host/admin controls, implicit hosting toggle
- **Plugins**: Can extend server functionality; use `go.plug.mod` for dependencies
- **Client build artifacts**: Embedded in server binary or served separately
- **RTMP broadcasting**: Support for streaming to external platforms (Twitch, YouTube)

## File Organization Patterns

- Go packages follow standard layout: `internal/` (private), `pkg/` (public), `cmd/` (executables)
- Client uses feature-based structure: components, store modules, utils
- Docker images: base image → app-specific image (extends base)
- Config namespacing: `desktop.*`, `member.*`, `session.*`, `webrtc.*`

## Testing Changes

1. Build client: `cd client && npm run build`
2. Build server: `cd server && ./build`
3. Test locally: `./server/bin/neko serve` (requires X11, GStreamer, PulseAudio)
4. Or use Docker: Modify Dockerfile → `./build` → `docker run`

## Related Resources

- Documentation: https://neko.m1k1o.net/
- API docs: See `webpage/docs/api/`
- Configuration reference: `webpage/docs/configuration/`
- Developer guide: `webpage/docs/developer-guide/`
