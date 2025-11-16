#!/bin/bash
# Neko Agent Installation Script for macOS
# One-line install: curl -fsSL https://neko.m1k1o.net/install-macos.sh | sh
# Or with options:  curl -fsSL https://neko.m1k1o.net/install-macos.sh | sh -s -- --build-from-source

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/neko"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/com.neko.agent.plist"
CURRENT_USER=$(whoami)
BUILD_FROM_SOURCE=false
INTERACTIVE=true

# Check if running interactively
if [ ! -t 0 ]; then
    INTERACTIVE=false
fi

# Parse arguments
for arg in "$@"; do
    case $arg in
        --build-from-source)
            BUILD_FROM_SOURCE=true
            shift
            ;;
        --non-interactive)
            INTERACTIVE=false
            shift
            ;;
        *)
            ;;
    esac
done

# Banner
echo
echo -e "${CYAN}${BOLD}"
cat << "EOF"
    _   __     __
   / | / /__  / /________
  /  |/ / _ \/ //_/ __ \
 / /|  /  __/ ,< / /_/ /
/_/ |_/\___/_/|_|\____/

  macOS Agent Installer
EOF
echo -e "${NC}"
echo -e "${BOLD}Virtual Desktop Streaming for macOS${NC}"
echo
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}✗ Error: This installer is for macOS only${NC}"
    echo -e "  Detected OS: $OSTYPE"
    exit 1
fi

echo -e "${GREEN}✓${NC} Running on macOS $(sw_vers -productVersion)"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    arm64)
        echo -e "${GREEN}✓${NC} Detected architecture: Apple Silicon (arm64)"
        ;;
    x86_64)
        echo -e "${GREEN}✓${NC} Detected architecture: Intel (x86_64)"
        ;;
    *)
        echo -e "${YELLOW}⚠${NC}  Unknown architecture: $ARCH (continuing anyway)"
        ;;
esac

echo

# Check for Homebrew
echo -e "${BLUE}▸${NC} Checking for Homebrew..."
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}  Homebrew not found. Installing...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo -e "${GREEN}  ✓ Homebrew installed${NC}"
else
    echo -e "${GREEN}  ✓ Homebrew found${NC}"
fi

# Check and install GStreamer
echo -e "${BLUE}▸${NC} Checking GStreamer..."
if ! command -v gst-launch-1.0 &> /dev/null; then
    echo -e "${YELLOW}  Installing GStreamer and plugins...${NC}"
    brew install gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
    echo -e "${GREEN}  ✓ GStreamer installed${NC}"
else
    echo -e "${GREEN}  ✓ GStreamer found${NC}"
fi

# Build or download binary
if [ "$BUILD_FROM_SOURCE" = true ]; then
    echo
    echo -e "${BLUE}▸${NC} Building from source..."

    # Check and install Go
    if ! command -v go &> /dev/null; then
        echo -e "${YELLOW}  Installing Go...${NC}"
        brew install go
        echo -e "${GREEN}  ✓ Go installed${NC}"
    else
        echo -e "${GREEN}  ✓ Go found ($(go version | awk '{print $3}'))${NC}"
    fi

    # Check if we're in the neko directory
    if [ -f "./server/cmd/neko/main.go" ]; then
        cd server
        echo -e "${BLUE}  Downloading dependencies...${NC}"
        go mod download
        echo -e "${BLUE}  Building binary...${NC}"
        CGO_ENABLED=1 go build -tags darwin -o bin/neko ./cmd/neko
        BINARY_PATH="$(pwd)/bin/neko"
        cd ..
    else
        echo -e "${YELLOW}  Cloning repository...${NC}"
        TEMP_DIR=$(mktemp -d)
        git clone https://github.com/m1k1o/neko.git "$TEMP_DIR"
        cd "$TEMP_DIR/server"
        echo -e "${BLUE}  Downloading dependencies...${NC}"
        go mod download
        echo -e "${BLUE}  Building binary...${NC}"
        CGO_ENABLED=1 go build -tags darwin -o bin/neko ./cmd/neko
        BINARY_PATH="$(pwd)/bin/neko"
        cd - > /dev/null
    fi

    if [ ! -f "$BINARY_PATH" ]; then
        echo -e "${RED}✗ Build failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}  ✓ Build successful${NC}"
else
    echo
    echo -e "${BLUE}▸${NC} Downloading latest release..."

    # Get latest release info from GitHub
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/m1k1o/neko/releases/latest)
    VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$VERSION" ]; then
        echo -e "${YELLOW}  Could not fetch latest release. Building from source instead...${NC}"
        BUILD_FROM_SOURCE=true
        exec "$0" --build-from-source
    fi

    # Try to download pre-built binary for macOS
    DOWNLOAD_URL="https://github.com/m1k1o/neko/releases/download/${VERSION}/neko-agent-${ARCH}-darwin"

    echo -e "${BLUE}  Fetching version ${VERSION}...${NC}"
    TEMP_DIR=$(mktemp -d)
    BINARY_PATH="$TEMP_DIR/neko"

    if curl -fsSL "$DOWNLOAD_URL" -o "$BINARY_PATH" 2>/dev/null; then
        chmod +x "$BINARY_PATH"
        echo -e "${GREEN}  ✓ Downloaded ${VERSION}${NC}"
    else
        echo -e "${YELLOW}  No pre-built binary available. Building from source...${NC}"
        BUILD_FROM_SOURCE=true
        exec "$0" --build-from-source
    fi
fi

echo

# Install binary
echo -e "${BLUE}▸${NC} Installing binary to ${INSTALL_DIR}..."
if [ -w "$INSTALL_DIR" ]; then
    cp "$BINARY_PATH" "$INSTALL_DIR/neko"
    chmod +x "$INSTALL_DIR/neko"
else
    sudo cp "$BINARY_PATH" "$INSTALL_DIR/neko"
    sudo chmod +x "$INSTALL_DIR/neko"
fi
echo -e "${GREEN}  ✓ Binary installed${NC}"

# Create config directory
echo -e "${BLUE}▸${NC} Creating configuration..."
mkdir -p "$CONFIG_DIR"

# Create config file
cat > "$CONFIG_DIR/agent-config.yaml" << 'EOF'
# Neko Agent Configuration for macOS

desktop:
  # Display is not used on macOS but required by config
  display: ":0"
  width: 1920
  height: 1080
  frame_rate: 30

capture:
  # Display setting (ignored on macOS, uses primary display)
  display: ":0"

  # Video codec
  video_codec: h264
  video_bitrate: 3072

  # Audio device (macOS will use default input)
  audio_device: "default"
  audio_codec: opus
  audio_bitrate: 128

webrtc:
  # ICE Lite mode for simplified networking
  ice_lite: true

  # Port range for WebRTC
  epr_min: 52000
  epr_max: 52100

  # Uncomment and configure if behind NAT
  # nat1to1:
  #   - "YOUR_PUBLIC_IP"

server:
  # Bind address
  bind: 127.0.0.1:8080

  # URL path prefix
  path_prefix: /

  # CORS settings
  cors:
    - "*"
EOF

echo -e "${GREEN}  ✓ Configuration created${NC}"

# Generate token
TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 64)

# Create LaunchAgent directory if needed
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/Library/Logs"

# Create LaunchAgent plist
echo -e "${BLUE}▸${NC} Setting up auto-start service..."
cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.neko.agent</string>

    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/neko</string>
        <string>agent</string>
        <string>--config</string>
        <string>$CONFIG_DIR/agent-config.yaml</string>
        <string>--token</string>
        <string>$TOKEN</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/neko-agent.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/neko-agent-error.log</string>
</dict>
</plist>
EOF

echo -e "${GREEN}  ✓ LaunchAgent configured${NC}"

# Save token to file
echo "$TOKEN" > "$CONFIG_DIR/.token"
chmod 600 "$CONFIG_DIR/.token"

echo
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${GREEN}${BOLD}✓ Installation Complete!${NC}"
echo
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Display connection info in a nice box
echo -e "${BOLD}Connection Information:${NC}"
echo
echo -e "  ${BOLD}Token:${NC}     ${YELLOW}${TOKEN}${NC}"
echo -e "  ${BOLD}WebSocket:${NC} ${BLUE}ws://localhost:8080/api/ws${NC}"
echo -e "  ${BOLD}Config:${NC}    ${CONFIG_DIR}/agent-config.yaml"
echo -e "  ${BOLD}Logs:${NC}      ~/Library/Logs/neko-agent.log"
echo

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${BOLD}Quick Start:${NC}"
echo

if [ "$INTERACTIVE" = true ]; then
    echo -e "  ${BOLD}1.${NC} Grant permissions (required on first run)"
    echo -e "     ${BLUE}System Settings → Privacy & Security → Screen Recording${NC}"
    echo -e "     ${BLUE}System Settings → Privacy & Security → Accessibility${NC}"
    echo
    echo -e "  ${BOLD}2.${NC} Test the agent:"
    echo -e "     ${GREEN}neko agent --token=${TOKEN:0:16}...${NC}"
    echo
    echo -e "  ${BOLD}3.${NC} Start background service:"
    echo -e "     ${GREEN}launchctl load ~/Library/LaunchAgents/com.neko.agent.plist${NC}"
    echo
    echo -e "  ${BOLD}4.${NC} View logs:"
    echo -e "     ${GREEN}tail -f ~/Library/Logs/neko-agent.log${NC}"
else
    echo -e "  ${BOLD}→${NC} Grant required permissions in System Settings"
    echo -e "  ${BOLD}→${NC} Run: ${GREEN}neko agent --token=\$(cat $CONFIG_DIR/.token)${NC}"
    echo -e "  ${BOLD}→${NC} Or start service: ${GREEN}launchctl load ~/Library/LaunchAgents/com.neko.agent.plist${NC}"
fi

echo
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${YELLOW}${BOLD}⚠️  Important: macOS Permissions${NC}"
echo
echo -e "  On first run, macOS will prompt for:"
echo -e "  ${BOLD}•${NC} ${BLUE}Screen Recording${NC} - to capture your display"
echo -e "  ${BOLD}•${NC} ${BLUE}Accessibility${NC} - to control mouse & keyboard"
echo
echo -e "  ${YELLOW}Restart the agent after granting permissions!${NC}"
echo

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${BOLD}Additional Commands:${NC}"
echo
echo -e "  ${BOLD}Stop service:${NC}"
echo -e "    launchctl unload ~/Library/LaunchAgents/com.neko.agent.plist"
echo
echo -e "  ${BOLD}Restart service:${NC}"
echo -e "    launchctl unload ~/Library/LaunchAgents/com.neko.agent.plist"
echo -e "    launchctl load ~/Library/LaunchAgents/com.neko.agent.plist"
echo
echo -e "  ${BOLD}Update config:${NC}"
echo -e "    nano $CONFIG_DIR/agent-config.yaml"
echo
echo -e "  ${BOLD}Remote access via SSH tunnel:${NC}"
echo -e "    ssh -L 8080:localhost:8080 $CURRENT_USER@your-mac.local"
echo

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${BOLD}Documentation:${NC} ${BLUE}https://neko.m1k1o.net${NC}"
echo -e "${BOLD}Source Code:${NC}    ${BLUE}https://github.com/m1k1o/neko${NC}"
echo
echo -e "Thank you for installing Neko! ${CYAN}🚀${NC}"
echo