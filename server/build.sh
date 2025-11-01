#!/bin/bash
# Build Neko for macOS (assumes GStreamer is already installed)

set -e

echo "Building Neko..."

# Set PKG_CONFIG_PATH
export PKG_CONFIG_PATH="/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/pkgconfig:$PKG_CONFIG_PATH"

# Build neko
CGO_ENABLED=1 go build -o bin/neko ./cmd/neko

echo ""
echo "✅ Build successful!"
echo "Binary: $(pwd)/bin/neko"
