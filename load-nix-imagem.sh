#!/usr/bin/env bash
# Load Nix-built OCI image into Docker
# This script uses the remote EC2 builder to create an OCI archive and loads it into Docker

set -euo pipefail

echo "Building nix2container image..."
nix build .#packages.x86_64-linux.image --print-out-paths

echo "Streaming OCI archive from remote builder..."
sudo -E bash -c '
  ssh -i /etc/nix/ec2_builder_ed25519 ec2-builder \
    "/nix/store/93r3qvc7q8v88z11j2pw45dlp2bqr75d-copy-to/bin/copy-to oci-archive:/home/admin/neko.tar >/dev/null 2>&1 && cat /home/admin/neko.tar && rm /home/admin/neko.tar" \
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
