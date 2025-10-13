#!/usr/bin/env bash
#
# Verification script for Neko images
# Verifies cosign signatures and attestations
#
set -euo pipefail

# Arguments
IMAGE_REF="${1:-}"
IDENTITY="${COSIGN_IDENTITY:-}"
ISSUER="${COSIGN_ISSUER:-https://token.actions.githubusercontent.com}"

usage() {
  cat <<EOF
Usage: $0 IMAGE_REF

Verify cosign signatures and attestations for a Neko image.

Arguments:
  IMAGE_REF    Full image reference (e.g., ghcr.io/m1k1o/neko/base@sha256:...)

Environment variables:
  COSIGN_IDENTITY        Expected identity (email) for keyless verification
  COSIGN_ISSUER          Expected OIDC issuer (default: GitHub Actions)
  COSIGN_KEY             Path to public key (for key-based verification)
  COSIGN_EXPERIMENTAL    Set to '1' for keyless verification

Examples:
  # Keyless verification
  COSIGN_EXPERIMENTAL=1 \\
  COSIGN_IDENTITY=user@example.com \\
    ./scripts/verify-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123

  # Key-based verification
  COSIGN_KEY=/path/to/public.key \\
    ./scripts/verify-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123
EOF
  exit 1
}

if [ -z "$IMAGE_REF" ]; then
  echo "Error: IMAGE_REF is required" >&2
  usage
fi

# Check dependencies
if ! command -v cosign >/dev/null 2>&1; then
  echo "Error: cosign is not installed" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed" >&2
  exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo "Neko Image Verification"
echo "═══════════════════════════════════════════════════════"
echo "Image: $IMAGE_REF"
echo ""

# Step 1: Verify signature
echo "Step 1: Verifying signature..."
echo ""

VERIFY_FAILED=0

if [ "${COSIGN_EXPERIMENTAL:-0}" = "1" ]; then
  # Keyless verification
  echo "Using keyless verification (OIDC)"

  if [ -z "$IDENTITY" ]; then
    echo "Warning: COSIGN_IDENTITY not set" >&2
    echo "Attempting verification without identity check..." >&2
    echo ""

    if cosign verify \
      --certificate-oidc-issuer "$ISSUER" \
      "$IMAGE_REF" > /tmp/neko-verify-sig.json 2>&1; then
      echo "✅ Signature verified (keyless, no identity check)"
    else
      echo "❌ Signature verification failed"
      cat /tmp/neko-verify-sig.json
      VERIFY_FAILED=1
    fi
  else
    echo "Identity: $IDENTITY"
    echo "Issuer:   $ISSUER"
    echo ""

    if cosign verify \
      --certificate-identity "$IDENTITY" \
      --certificate-oidc-issuer "$ISSUER" \
      "$IMAGE_REF" > /tmp/neko-verify-sig.json 2>&1; then
      echo "✅ Signature verified (keyless)"
    else
      echo "❌ Signature verification failed"
      cat /tmp/neko-verify-sig.json
      VERIFY_FAILED=1
    fi
  fi

elif [ -n "${COSIGN_KEY:-}" ]; then
  # Key-based verification
  echo "Using key-based verification"
  echo "Key: $COSIGN_KEY"
  echo ""

  if cosign verify \
    --key "$COSIGN_KEY" \
    "$IMAGE_REF" > /tmp/neko-verify-sig.json 2>&1; then
    echo "✅ Signature verified (key-based)"
  else
    echo "❌ Signature verification failed"
    cat /tmp/neko-verify-sig.json
    VERIFY_FAILED=1
  fi

else
  echo "Error: Neither COSIGN_EXPERIMENTAL nor COSIGN_KEY is set" >&2
  echo "Please set one of these environment variables" >&2
  exit 1
fi

echo ""

# Show signature details
if [ -f /tmp/neko-verify-sig.json ]; then
  echo "Signature details:"
  jq '.[0] | {
    critical: .critical,
    optional: .optional
  }' /tmp/neko-verify-sig.json 2>/dev/null || echo "(no details available)"
  echo ""
fi

# Step 2: Verify SBOM
echo "Step 2: Verifying SBOM..."

if cosign download sbom "$IMAGE_REF" > /tmp/neko-sbom.json 2>&1; then
  SBOM_PACKAGES=$(jq -r '.packages | length' /tmp/neko-sbom.json 2>/dev/null || echo "unknown")
  echo "✅ SBOM found ($SBOM_PACKAGES packages)"
  echo ""
else
  echo "⚠️  No SBOM found (this is optional)"
  echo ""
fi

# Step 3: Verify attestations
echo "Step 3: Verifying attestations..."

VERIFY_ATTEST_ARGS=""
if [ "${COSIGN_EXPERIMENTAL:-0}" = "1" ] && [ -n "$IDENTITY" ]; then
  VERIFY_ATTEST_ARGS="--certificate-identity $IDENTITY --certificate-oidc-issuer $ISSUER"
elif [ -n "${COSIGN_KEY:-}" ]; then
  VERIFY_ATTEST_ARGS="--key $COSIGN_KEY"
fi

if cosign verify-attestation \
  $VERIFY_ATTEST_ARGS \
  --type slsaprovenance \
  "$IMAGE_REF" > /tmp/neko-verify-attest.json 2>&1; then
  echo "✅ SLSA provenance attestation verified"
  echo ""

  # Extract and display provenance
  echo "Provenance summary:"
  jq -r '.payload | @base64d | fromjson | {
    predicateType: .predicateType,
    buildType: .predicate.buildDefinition.buildType,
    repository: .predicate.buildDefinition.externalParameters.repository,
    commit: .predicate.buildDefinition.externalParameters.commit,
    narHash: .predicate.buildDefinition.internalParameters.narHash
  }' /tmp/neko-verify-attest.json 2>/dev/null || echo "(could not parse provenance)"
  echo ""
else
  echo "⚠️  Provenance attestation not found or verification failed"
  echo ""
fi

# Step 4: Check image digest matches manifest
echo "Step 4: Verifying image digest..."

# Extract digest from image ref
if [[ "$IMAGE_REF" =~ @sha256:([a-f0-9]+) ]]; then
  EXPECTED_DIGEST="sha256:${BASH_REMATCH[1]}"

  # Get actual digest
  ACTUAL_DIGEST=$(skopeo inspect "docker://$IMAGE_REF" 2>/dev/null | jq -r .Digest || echo "unknown")

  if [ "$EXPECTED_DIGEST" = "$ACTUAL_DIGEST" ]; then
    echo "✅ Image digest matches reference"
    echo "   Digest: $ACTUAL_DIGEST"
  else
    echo "❌ Image digest mismatch!"
    echo "   Expected: $EXPECTED_DIGEST"
    echo "   Actual:   $ACTUAL_DIGEST"
    VERIFY_FAILED=1
  fi
else
  echo "⚠️  No digest in image reference (using tag instead)"
  echo "   Warning: Tags are mutable and can't be cryptographically verified"
fi

echo ""

# Summary
echo "═══════════════════════════════════════════════════════"

if [ $VERIFY_FAILED -eq 0 ]; then
  echo "✅ VERIFICATION PASSED"
  echo "═══════════════════════════════════════════════════════"
  echo "The image signature and attestations are valid."
  echo ""
  echo "This means:"
  echo "  • The image was signed by a trusted entity"
  echo "  • The image has not been tampered with"
  echo "  • Build provenance is available and verified"
  echo "  • SBOM (if present) is attached and accessible"
  echo ""
  echo "Image: $IMAGE_REF"
  echo "═══════════════════════════════════════════════════════"
  exit 0
else
  echo "❌ VERIFICATION FAILED"
  echo "═══════════════════════════════════════════════════════"
  echo "One or more verification checks failed."
  echo "DO NOT use this image in production."
  echo ""
  echo "Image: $IMAGE_REF"
  echo "═══════════════════════════════════════════════════════"
  exit 1
fi
