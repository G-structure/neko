#!/usr/bin/env bash
#
# Cosign image signing wrapper for Neko
# Supports both keyless (OIDC) and key-based signing
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
SIGNING_MODE="${SIGNING_MODE:-keyless}"
IMAGE_REF="${1:-}"

usage() {
  cat <<EOF
Usage: $0 IMAGE_REF

Sign a Neko OCI image with cosign.

Arguments:
  IMAGE_REF    Full image reference (e.g., ghcr.io/m1k1o/neko/base@sha256:...)

Environment variables:
  SIGNING_MODE       Signing mode: 'keyless' (default) or 'key' or 'tdx'
  COSIGN_KEY         Path to signing key (for SIGNING_MODE=key)
  TDX_ENABLED        Set to '1' to use TDX-attested signing (calls attested-key script)
  COSIGN_YES         Set to 'true' to skip confirmation prompts

Examples:
  # Keyless signing (default, uses OIDC)
  COSIGN_EXPERIMENTAL=1 ./scripts/sign-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123

  # Key-based signing
  SIGNING_MODE=key COSIGN_KEY=/path/to/key ./scripts/sign-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123

  # TDX-attested signing
  TDX_ENABLED=1 ./scripts/sign-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123
EOF
  exit 1
}

# Check arguments
if [ -z "$IMAGE_REF" ]; then
  echo "Error: IMAGE_REF is required" >&2
  usage
fi

# Check dependencies
if ! command -v cosign >/dev/null 2>&1; then
  echo "Error: cosign is not installed" >&2
  echo "Install with: nix-shell -p cosign" >&2
  exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo "Neko Image Signing"
echo "═══════════════════════════════════════════════════════"
echo "Image:        $IMAGE_REF"
echo "Signing mode: $SIGNING_MODE"
echo ""

# Handle TDX signing if enabled
if [ "${TDX_ENABLED:-0}" = "1" ] || [ "$SIGNING_MODE" = "tdx" ]; then
  echo "TDX signing enabled - obtaining attested signing key..."

  # Source the attested-key script to set up signing credentials
  if [ -f "$SCRIPT_DIR/attested-key" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/attested-key"
  else
    echo "Error: attested-key script not found at $SCRIPT_DIR/attested-key" >&2
    exit 1
  fi

  echo "Attested signing key obtained"
fi

# Perform signing based on mode
case "$SIGNING_MODE" in
  keyless)
    echo "Using keyless signing (OIDC via Fulcio/Rekor)"
    echo ""

    # Ensure experimental mode is enabled
    export COSIGN_EXPERIMENTAL=1

    # Sign with keyless (stores signature in Rekor transparency log)
    echo "Signing image..."
    cosign sign ${COSIGN_YES:+--yes} "$IMAGE_REF"

    echo ""
    echo "✅ Image signed successfully (keyless)"
    echo ""
    echo "Signature stored in Rekor transparency log"
    echo "Verify with:"
    echo "  COSIGN_EXPERIMENTAL=1 cosign verify \\"
    echo "    --certificate-identity <your-email> \\"
    echo "    --certificate-oidc-issuer https://token.actions.githubusercontent.com \\"
    echo "    $IMAGE_REF"
    ;;

  key)
    echo "Using key-based signing"

    if [ -z "${COSIGN_KEY:-}" ]; then
      echo "Error: COSIGN_KEY environment variable is required for key-based signing" >&2
      exit 1
    fi

    if [ ! -f "$COSIGN_KEY" ]; then
      echo "Error: Signing key not found at $COSIGN_KEY" >&2
      exit 1
    fi

    echo "Key: $COSIGN_KEY"
    echo ""

    # Sign with key
    echo "Signing image..."
    cosign sign --key "$COSIGN_KEY" ${COSIGN_YES:+--yes} "$IMAGE_REF"

    echo ""
    echo "✅ Image signed successfully (key-based)"
    echo ""
    echo "Verify with:"
    echo "  cosign verify --key $COSIGN_KEY $IMAGE_REF"
    ;;

  tdx)
    echo "Using TDX-attested signing"

    # The attested-key script should have set up COSIGN_KEY or similar
    if [ -z "${COSIGN_KEY:-}" ]; then
      echo "Error: TDX attestation did not provide a signing key" >&2
      exit 1
    fi

    echo "Signing with TDX-attested key..."
    cosign sign --key "$COSIGN_KEY" ${COSIGN_YES:+--yes} "$IMAGE_REF"

    # Clean up ephemeral key
    if [ -f "$COSIGN_KEY" ]; then
      shred -u "$COSIGN_KEY" 2>/dev/null || rm -f "$COSIGN_KEY"
    fi

    echo ""
    echo "✅ Image signed successfully (TDX-attested)"
    ;;

  *)
    echo "Error: Unknown signing mode: $SIGNING_MODE" >&2
    echo "Valid modes: keyless, key, tdx" >&2
    exit 1
    ;;
esac

# Verify the signature was created
echo ""
echo "Fetching signature to verify it was created..."
cosign tree "$IMAGE_REF" || echo "Warning: Could not display signature tree"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "Signing complete!"
echo "═══════════════════════════════════════════════════════"
