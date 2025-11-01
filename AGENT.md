# Neko Agent Mode

A minimal, single-user version of Neko for desktop streaming without multi-user features.

## Overview

The agent mode provides a stripped-down Neko server that:
- Runs on any Linux desktop with X11
- Single pre-authenticated session (no login flow)
- Minimal resource usage
- Simple token-based authentication
- Compatible with existing Neko clients

## Quick Start

### Automated Installation (Linux)

```bash
./scripts/install-agent.sh
```

### Manual Installation

1. **Build the agent:**
```bash
# With Nix
nix build .#nekoServer

# Or with Go
cd server && ./build core
```

2. **Run directly:**
```bash
# Generate a token
TOKEN=$(openssl rand -hex 32)

# Run the agent
./neko agent --token=$TOKEN \
  --desktop.display=:0 \
  --server.bind=0.0.0.0:8080
```

3. **Connect your client:**
   - WebSocket URL: `ws://your-server:8080/api/ws`
   - Password/Token: Use the token from above

## Configuration

### Command Line Flags

```bash
./neko agent \
  --token=your-secure-token \
  --desktop.display=:0 \
  --desktop.width=1920 \
  --desktop.height=1080 \
  --capture.video_codec=h264 \
  --webrtc.ice_lite=true \
  --server.bind=127.0.0.1:8080
```

### Configuration File

Use the provided `scripts/agent-config.yaml`:

```bash
./neko agent --config scripts/agent-config.yaml --token=your-token
```

### Environment Variables

All settings can be set via environment variables with `NEKO_` prefix:

```bash
export NEKO_DESKTOP_DISPLAY=:0
export NEKO_SERVER_BIND=0.0.0.0:8080
export NEKO_AGENT_TOKEN=your-secure-token
./neko agent
```

## Systemd Service

For auto-start on boot:

1. **Install the service file:**
```bash
sudo cp scripts/neko-agent.service /etc/systemd/system/neko-agent@.service
```

2. **Start for your user:**
```bash
sudo systemctl start neko-agent@$USER
```

3. **Enable auto-start:**
```bash
sudo systemctl enable neko-agent@$USER
```

4. **Check logs:**
```bash
journalctl -u neko-agent@$USER -f
```

## Architecture

The agent mode reuses Neko's core components:
- **Desktop Manager** - X11 display control
- **Capture Manager** - GStreamer video/audio capture
- **WebRTC Manager** - Streaming via Pion WebRTC
- **WebSocket Manager** - Signaling and control

But simplifies:
- **Single Session Manager** - One hardcoded session, no user management
- **Minimal API** - Only health, stats, and WebSocket endpoints
- **No plugins** - Plugin system disabled
- **No admin features** - No member management, locks, or broadcasts

## Differences from Full Neko

| Feature | Full Neko | Agent Mode |
|---------|-----------|------------|
| Multi-user | ✅ | ❌ |
| Authentication | Username/Password | Token only |
| Session management | Full CRUD | Single fixed session |
| Admin controls | ✅ | ❌ |
| Plugins | ✅ | ❌ |
| Host control | Multiple users | Always agent |
| API endpoints | Full REST API | Minimal (health, stats) |

## Security

For production use:
1. Use a strong, randomly generated token
2. Run behind a reverse proxy with TLS
3. Use firewall rules to restrict access
4. Consider VPN for remote access
5. Use the systemd security hardening options

## Troubleshooting

### Cannot connect to X11 display
```bash
# Check DISPLAY variable
echo $DISPLAY

# Allow X11 connections (if needed)
xhost +local:
```

### No audio capture
```bash
# List audio sources
pactl list sources

# Use the monitor device for desktop audio
--capture.audio_device=auto_null.monitor
```

### WebRTC connection fails
```bash
# For LAN/VPN, use ICE Lite mode
--webrtc.ice_lite=true

# For internet, configure STUN/TURN
--webrtc.ice_servers='[{"urls":["stun:stun.l.google.com:19302"]}]'
```

## Development

The agent implementation is in:
- `server/cmd/agent.go` - Command definition
- `server/internal/agent/session.go` - Single session manager
- `server/internal/agent/api.go` - Minimal API endpoints

To modify, edit these files and rebuild with:
```bash
cd server && ./build core
```