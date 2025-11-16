# Neko macOS Installation

## Quick Install

Install Neko agent on macOS with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/m1k1o/neko/master/scripts/install-agent-macos.sh | sh
```

### Installation Options

**Build from source instead of downloading binary:**
```bash
curl -fsSL https://raw.githubusercontent.com/m1k1o/neko/master/scripts/install-agent-macos.sh | sh -s -- --build-from-source
```

**Run the script directly (if already downloaded):**
```bash
./scripts/install-agent-macos.sh
```

## What Gets Installed

The installer will:

1. ✅ Install Homebrew (if not present)
2. ✅ Install GStreamer and required plugins
3. ✅ Download the latest Neko binary (or build from source)
4. ✅ Create configuration at `~/.config/neko/agent-config.yaml`
5. ✅ Set up LaunchAgent for auto-start
6. ✅ Generate a secure connection token

## System Requirements

- **macOS**: 10.15 (Catalina) or later
- **Architecture**: Apple Silicon (arm64) or Intel (x86_64)
- **Disk Space**: ~500MB for dependencies

## macOS Permissions

The agent requires two system permissions:

### 1. Screen Recording
**Location:** System Settings → Privacy & Security → Screen Recording

Allows Neko to capture your screen content.

### 2. Accessibility
**Location:** System Settings → Privacy & Security → Accessibility

Allows Neko to control mouse and keyboard input.

**⚠️ Important:** You must restart the agent after granting permissions.

## Quick Start

After installation:

### Test the agent
```bash
neko agent --token=$(cat ~/.config/neko/.token)
```

### Start as background service
```bash
launchctl load ~/Library/LaunchAgents/com.neko.agent.plist
```

### View logs
```bash
tail -f ~/Library/Logs/neko-agent.log
```

## Configuration

Edit the configuration file:
```bash
nano ~/.config/neko/agent-config.yaml
```

After making changes, restart the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.neko.agent.plist
launchctl load ~/Library/LaunchAgents/com.neko.agent.plist
```

## Connecting to Your Agent

### Local Connection
```
WebSocket URL: ws://localhost:8080/api/ws
Token: [shown during installation]
```

### Remote Connection (via SSH tunnel)
```bash
ssh -L 8080:localhost:8080 your-username@your-mac.local
```

Then connect to `ws://localhost:8080/api/ws` from your local machine.

## Troubleshooting

### Check if agent is running
```bash
launchctl list | grep neko
```

### View recent logs
```bash
tail -n 100 ~/Library/Logs/neko-agent.log
```

### Completely remove Neko
```bash
# Stop service
launchctl unload ~/Library/LaunchAgents/com.neko.agent.plist

# Remove files
rm -f /usr/local/bin/neko
rm -rf ~/.config/neko
rm -f ~/Library/LaunchAgents/com.neko.agent.plist
rm -f ~/Library/Logs/neko-agent*.log
```

### Permission issues
If you get permission errors:
1. Open System Settings → Privacy & Security
2. Look for pending permission requests at the bottom
3. Grant both Screen Recording and Accessibility permissions
4. Restart the agent

### GStreamer issues
Reinstall GStreamer:
```bash
brew reinstall gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
```

## Manual Installation

If you prefer to install manually, see the [macOS documentation](./MACOS.md).

## Next Steps

- Read the [Quick Start Guide](./MACOS_QUICKSTART.md)
- Configure [advanced settings](./config.yml)
- Set up [remote access](./webpage/docs/reverse-proxy-setup.md)

## Documentation

- Website: https://neko.m1k1o.net
- GitHub: https://github.com/m1k1o/neko
- Issues: https://github.com/m1k1o/neko/issues
