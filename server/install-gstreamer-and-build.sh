#!/bin/bash
# Install GStreamer and build Neko for macOS

set -e

echo "Installing GStreamer for macOS..."

# Download GStreamer packages
echo "Downloading GStreamer runtime..."
sudo curl -L -o /tmp/gstreamer-runtime.pkg https://gstreamer.freedesktop.org/data/pkg/osx/1.26.7/gstreamer-1.0-1.26.7-universal.pkg

echo "Downloading GStreamer development package..."
sudo curl -L -o /tmp/gstreamer-devel.pkg https://gstreamer.freedesktop.org/data/pkg/osx/1.26.7/gstreamer-1.0-devel-1.26.7-universal.pkg

# Install packages
echo "Installing GStreamer runtime..."
sudo installer -pkg /tmp/gstreamer-runtime.pkg -target /

echo "Installing GStreamer development package..."
sudo installer -pkg /tmp/gstreamer-devel.pkg -target /

# Clean up
rm /tmp/gstreamer-runtime.pkg /tmp/gstreamer-devel.pkg

echo "GStreamer installed successfully!"
echo ""
echo "Building Neko..."

# Set PKG_CONFIG_PATH
export PKG_CONFIG_PATH="/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/pkgconfig:$PKG_CONFIG_PATH"

# Build neko
CGO_ENABLED=1 go build -o bin/neko ./cmd/neko

echo ""
echo "✅ Build successful!"
echo "Binary: $(pwd)/bin/neko"
