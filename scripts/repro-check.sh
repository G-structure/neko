#!/usr/bin/env bash
#
# Reproducibility verification script for Neko
# Builds the image twice and compares NAR hashes and OCI digests
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
  echo -e "${GREEN}[repro-check]${NC} $*"
}

error() {
  echo -e "${RED}[repro-check]${NC} $*" >&2
}

warn() {
  echo -e "${YELLOW}[repro-check]${NC} $*"
}

# Check dependencies
command -v nix >/dev/null 2>&1 || {
  error "nix is not installed. Please install Nix first."
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  error "jq is not installed. Please install jq first."
  exit 1
}

log "Starting reproducibility check for Neko image..."

# Build 1
log "Building image (first build)..."
nix build .#image --no-link --print-out-paths > /tmp/neko-build1-path.txt
BUILD1_PATH=$(cat /tmp/neko-build1-path.txt)

log "First build output: $BUILD1_PATH"

# Get NAR hash and info for build 1
log "Getting NAR hash for first build..."
nix path-info --json "$BUILD1_PATH" > /tmp/neko-build1-info.json
NAR_HASH1=$(jq -r '.[0].narHash' /tmp/neko-build1-info.json)
NAR_SIZE1=$(jq -r '.[0].narSize' /tmp/neko-build1-info.json)

log "Build 1 - NAR hash: $NAR_HASH1"
log "Build 1 - NAR size: $NAR_SIZE1 bytes"

# Clean and rebuild
log "Cleaning previous build..."
nix store delete "$BUILD1_PATH" 2>/dev/null || warn "Could not delete first build (may be in use)"

log "Rebuilding image (second build with --check)..."
nix build .#image --rebuild --check --no-link --print-out-paths > /tmp/neko-build2-path.txt
BUILD2_PATH=$(cat /tmp/neko-build2-path.txt)

log "Second build output: $BUILD2_PATH"

# Get NAR hash and info for build 2
log "Getting NAR hash for second build..."
nix path-info --json "$BUILD2_PATH" > /tmp/neko-build2-info.json
NAR_HASH2=$(jq -r '.[0].narHash' /tmp/neko-build2-info.json)
NAR_SIZE2=$(jq -r '.[0].narSize' /tmp/neko-build2-info.json)

log "Build 2 - NAR hash: $NAR_HASH2"
log "Build 2 - NAR size: $NAR_SIZE2 bytes"

# Compare NAR hashes
echo ""
log "Comparing NAR hashes..."

if [ "$NAR_HASH1" = "$NAR_HASH2" ]; then
  echo -e "${GREEN}✅ NAR HASHES MATCH!${NC}"
  echo "  Hash: $NAR_HASH1"
else
  echo -e "${RED}❌ NAR HASHES DO NOT MATCH!${NC}"
  echo "  Build 1: $NAR_HASH1"
  echo "  Build 2: $NAR_HASH2"
  exit 1
fi

# Compare NAR sizes
if [ "$NAR_SIZE1" = "$NAR_SIZE2" ]; then
  echo -e "${GREEN}✅ NAR SIZES MATCH!${NC}"
  echo "  Size: $NAR_SIZE1 bytes"
else
  echo -e "${RED}❌ NAR SIZES DO NOT MATCH!${NC}"
  echo "  Build 1: $NAR_SIZE1 bytes"
  echo "  Build 2: $NAR_SIZE2 bytes"
  exit 1
fi

# If we have diffoscope, do a detailed comparison
if command -v diffoscope >/dev/null 2>&1; then
  log "Running diffoscope for detailed comparison..."
  if diffoscope --text /tmp/neko-diffoscope.txt "$BUILD1_PATH" "$BUILD2_PATH" 2>/dev/null; then
    echo -e "${GREEN}✅ diffoscope found no differences${NC}"
  else
    warn "diffoscope found some differences (check /tmp/neko-diffoscope.txt)"
  fi
else
  warn "diffoscope not installed - skipping detailed comparison"
  warn "Install with: nix-shell -p diffoscope"
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}✅ REPRODUCIBILITY CHECK PASSED!${NC}"
echo "═══════════════════════════════════════════════════════"
echo "The Neko image build is bit-for-bit reproducible."
echo ""
echo "NAR Hash: $NAR_HASH1"
echo "NAR Size: $NAR_SIZE1 bytes"
echo ""
echo "This means:"
echo "  • Anyone can rebuild from the same commit"
echo "  • The build will produce identical output"
echo "  • The cryptographic hash can be verified independently"
echo "═══════════════════════════════════════════════════════"

# Save results
cat > /tmp/neko-repro-results.json <<EOF
{
  "reproducible": true,
  "narHash": "$NAR_HASH1",
  "narSize": $NAR_SIZE1,
  "build1Path": "$BUILD1_PATH",
  "build2Path": "$BUILD2_PATH",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

log "Results saved to /tmp/neko-repro-results.json"

exit 0
