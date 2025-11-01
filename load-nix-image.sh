#!/usr/bin/env bash
# Load Nix-built OCI image into Docker
# This script uses the remote EC2 builder to create an OCI archive and loads it into Docker

set -euo pipefail

echo "Building nix2container image on remote builder..."
BUILD_OUTPUT=$(nix build .#packages.x86_64-linux.image --print-out-paths --no-link)

# Extract the store path (last line of output)
STORE_PATH=$(echo "$BUILD_OUTPUT" | tail -1)
echo "Built image at: $STORE_PATH"

# Get the copy-to script path from the store path
COPY_TO_PATH="${STORE_PATH}/bin/copy-to"

echo "Copying OCI archive from remote builder..."
echo "Using copy-to path: $COPY_TO_PATH"
sudo -E bash -c '
  ssh -i /Users/wikigen/Downloads/nix\ builder\ was.pem ec2-builder \
    "/nix/store/dxx17layj3y2sp7g95q4rfgv0sx5cbq6-copy-to/bin/copy-to oci-archive:/home/admin/neko.tar >/dev/null 2>&1 && cat /home/admin/neko.tar && rm /home/admin/neko.tar" \
    > neko-image.tar
'

echo "Loading image into Docker..."
LOAD_OUTPUT=$(docker load < neko-image.tar)
echo "$LOAD_OUTPUT"

echo "Tagging image..."
IMAGE_ID=$(echo "$LOAD_OUTPUT" | grep -o 'sha256:[a-f0-9]*' | head -1)
if [ -z "$IMAGE_ID" ]; then
  echo "Error: Could not extract image ID from docker load output"
  exit 1
fi
docker tag "$IMAGE_ID" ghcr.io/m1k1o/neko/base:latest

echo "Cleaning up..."
rm neko-image.tar

echo "✓ Success! Image loaded:"
docker images | grep "ghcr.io/m1k1o/neko/base"
