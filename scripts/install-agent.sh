#!/bin/bash
# Neko Agent Installation Script
# This script helps install and configure the Neko agent on a Linux desktop

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/neko"
SERVICE_FILE="/etc/systemd/system/neko-agent@.service"
CURRENT_USER=$(whoami)

echo -e "${GREEN}Neko Agent Installation Script${NC}"
echo "================================"
echo

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}Error: This script is for Linux only${NC}"
    exit 1
fi

# Check for required dependencies
echo "Checking dependencies..."

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}✗ $1 is not installed${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $1 is installed${NC}"
        return 0
    fi
}

MISSING_DEPS=0

# Check X11
if [ -z "$DISPLAY" ]; then
    echo -e "${YELLOW}⚠ DISPLAY not set. Will use :0${NC}"
    export DISPLAY=:0
fi

# Check for xorg
if ! check_command Xorg; then
    echo "  Install with: sudo apt-get install xorg (Debian/Ubuntu)"
    echo "                sudo dnf install xorg-x11-server-Xorg (Fedora)"
    MISSING_DEPS=1
fi

# Check for GStreamer
if ! check_command gst-launch-1.0; then
    echo "  Install with: sudo apt-get install gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good"
    MISSING_DEPS=1
fi

# Check for PulseAudio
if ! check_command pactl; then
    echo -e "${YELLOW}⚠ PulseAudio not found (optional for audio)${NC}"
    echo "  Install with: sudo apt-get install pulseaudio"
fi

if [ $MISSING_DEPS -eq 1 ]; then
    echo
    echo -e "${RED}Please install missing dependencies and run this script again${NC}"
    exit 1
fi

echo

# Check if neko binary exists
if [ ! -f "./result/bin/neko" ] && [ ! -f "./server/bin/neko" ]; then
    echo -e "${YELLOW}Neko binary not found. Building...${NC}"

    # Try to build with nix if available
    if command -v nix &> /dev/null; then
        echo "Building with Nix..."
        nix build .#nekoServer
        NEKO_BIN="./result/bin/neko"
    elif command -v go &> /dev/null; then
        echo "Building with Go..."
        cd server
        ./build core
        cd ..
        NEKO_BIN="./server/bin/neko"
    else
        echo -e "${RED}Cannot build: neither Nix nor Go is installed${NC}"
        exit 1
    fi
else
    if [ -f "./result/bin/neko" ]; then
        NEKO_BIN="./result/bin/neko"
    else
        NEKO_BIN="./server/bin/neko"
    fi
fi

echo -e "${GREEN}Found neko binary at: $NEKO_BIN${NC}"

# Test if agent command exists
if ! $NEKO_BIN agent --help &> /dev/null; then
    echo -e "${RED}Error: The neko binary doesn't have the agent command${NC}"
    echo "Please rebuild with the agent patches applied"
    exit 1
fi

echo

# Installation steps
echo "Installation Steps:"
echo "1. Copy neko binary to $INSTALL_DIR"
echo "2. Create config directory at $CONFIG_DIR"
echo "3. Install systemd service file"
echo "4. Generate authentication token"
echo

read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Install binary
echo "Installing neko binary..."
sudo cp $NEKO_BIN $INSTALL_DIR/neko
sudo chmod +x $INSTALL_DIR/neko

# Create config directory
echo "Creating config directory..."
sudo mkdir -p $CONFIG_DIR

# Copy config file
echo "Installing configuration..."
sudo cp scripts/agent-config.yaml $CONFIG_DIR/

# Install systemd service
echo "Installing systemd service..."
sudo cp scripts/neko-agent.service $SERVICE_FILE

# Generate token
TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | base64)
echo

echo -e "${GREEN}Installation Complete!${NC}"
echo
echo "To start the agent:"
echo "  1. Edit the configuration (optional):"
echo "     sudo nano $CONFIG_DIR/agent-config.yaml"
echo
echo "  2. Start the service for your user:"
echo "     sudo systemctl start neko-agent@$CURRENT_USER"
echo
echo "  3. Enable auto-start on boot:"
echo "     sudo systemctl enable neko-agent@$CURRENT_USER"
echo
echo "  4. Check service status:"
echo "     sudo systemctl status neko-agent@$CURRENT_USER"
echo
echo "  5. View logs:"
echo "     journalctl -u neko-agent@$CURRENT_USER -f"
echo
echo -e "${YELLOW}Your connection token is: $TOKEN${NC}"
echo "Save this token - you'll need it to connect your client"
echo
echo "To use the token, either:"
echo "  - Set environment variable: NEKO_AGENT_TOKEN=$TOKEN"
echo "  - Or add --token=$TOKEN when starting the agent"
echo
echo "WebSocket URL: ws://localhost:8080/api/ws"
echo
echo "For remote access, replace localhost with your server IP"