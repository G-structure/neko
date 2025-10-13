#!/usr/bin/env bash
#
# Attestation script for Neko images
# Generates and attaches SLSA provenance and SBOM
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Arguments
IMAGE_REF="${1:-}"
SBOM_FILE="${SBOM_FILE:-sbom.spdx.json}"
PROVENANCE_FILE="${PROVENANCE_FILE:-provenance.json}"

usage() {
  cat <<EOF
Usage: $0 IMAGE_REF

Generate and attach SLSA provenance and SBOM attestations to a Neko image.

Arguments:
  IMAGE_REF    Full image reference (e.g., ghcr.io/m1k1o/neko/base@sha256:...)

Environment variables:
  SBOM_FILE          SBOM output file (default: sbom.spdx.json)
  PROVENANCE_FILE    Provenance output file (default: provenance.json)
  COSIGN_EXPERIMENTAL Set to '1' for keyless attestation

Examples:
  # Keyless attestation
  COSIGN_EXPERIMENTAL=1 ./scripts/attest-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123

  # Key-based attestation
  COSIGN_KEY=/path/to/key ./scripts/attest-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123
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
echo "Neko Image Attestation"
echo "═══════════════════════════════════════════════════════"
echo "Image:      $IMAGE_REF"
echo "SBOM:       $SBOM_FILE"
echo "Provenance: $PROVENANCE_FILE"
echo ""

cd "$PROJECT_ROOT"

# Step 1: Generate SBOM
echo "Step 1: Generating SBOM..."

if command -v syft >/dev/null 2>&1; then
  echo "Using syft to generate SBOM..."
  syft "$IMAGE_REF" -o spdx-json > "$SBOM_FILE"
  echo "✅ SBOM generated with syft"
elif [ -f "sbom/sbomnix.nix" ]; then
  echo "Using sbomnix (Nix-aware SBOM)..."
  nix run .#sbom > "$SBOM_FILE"
  echo "✅ SBOM generated with sbomnix"
else
  echo "⚠️  Warning: No SBOM generator found (syft or sbomnix)"
  echo "Creating minimal SBOM..."

  # Create a minimal SBOM
  cat > "$SBOM_FILE" <<EOF
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "neko-image",
  "documentNamespace": "https://github.com/m1k1o/neko/sbom/$(uuidgen || echo 'manual')",
  "creationInfo": {
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "creators": ["Tool: neko-attest-script"]
  },
  "packages": []
}
EOF
  echo "⚠️  Minimal SBOM created"
fi

echo "SBOM size: $(wc -c < "$SBOM_FILE") bytes"
echo ""

# Step 2: Generate SLSA provenance
echo "Step 2: Generating SLSA provenance..."

# Get git info
GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_TAG=$(git describe --exact-match --tags HEAD 2>/dev/null || echo "")

# Get NAR hash
NAR_HASH=$(nix path-info --json .#image 2>/dev/null | jq -r '.[0].narHash' || echo "unknown")

# Get image digest
IMAGE_DIGEST=$(echo "$IMAGE_REF" | grep -oP 'sha256:[a-f0-9]+' || skopeo inspect "docker://$IMAGE_REF" 2>/dev/null | jq -r '.Digest' || echo "unknown")

# Create SLSA provenance (v1.0 format)
cat > "$PROVENANCE_FILE" <<EOF
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "predicateType": "https://slsa.dev/provenance/v1",
  "subject": [
    {
      "name": "${IMAGE_REF%%@*}",
      "digest": {
        "$(echo "$IMAGE_DIGEST" | cut -d: -f1)": "$(echo "$IMAGE_DIGEST" | cut -d: -f2)"
      }
    }
  ],
  "predicate": {
    "buildDefinition": {
      "buildType": "https://nix.dev/flake-build@v1",
      "externalParameters": {
        "repository": "https://github.com/m1k1o/neko",
        "ref": "$GIT_BRANCH",
        "commit": "$GIT_COMMIT",
        "tag": "$GIT_TAG"
      },
      "internalParameters": {
        "narHash": "$NAR_HASH"
      },
      "resolvedDependencies": []
    },
    "runDetails": {
      "builder": {
        "id": "https://github.com/NixOS/nix"
      },
      "metadata": {
        "invocationId": "$GIT_COMMIT",
        "startedOn": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "finishedOn": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      },
      "byproducts": [
        {
          "name": "narHash",
          "digest": {
            "$(echo "$NAR_HASH" | cut -d- -f1)": "$(echo "$NAR_HASH" | cut -d- -f2)"
          }
        }
      ]
    }
  }
}
EOF

echo "✅ Provenance generated"
echo "Provenance size: $(wc -c < "$PROVENANCE_FILE") bytes"
echo ""

# Step 3: Attach SBOM to image
echo "Step 3: Attaching SBOM to image..."
cosign attach sbom --sbom "$SBOM_FILE" "$IMAGE_REF"
echo "✅ SBOM attached"
echo ""

# Step 4: Attest provenance
echo "Step 4: Attesting provenance..."

ATTEST_ARGS=""
if [ "${COSIGN_EXPERIMENTAL:-0}" = "1" ]; then
  echo "Using keyless attestation (OIDC)"
  ATTEST_ARGS="--yes"
elif [ -n "${COSIGN_KEY:-}" ]; then
  echo "Using key-based attestation"
  ATTEST_ARGS="--key $COSIGN_KEY"
fi

cosign attest \
  $ATTEST_ARGS \
  --predicate "$PROVENANCE_FILE" \
  --type slsaprovenance \
  "$IMAGE_REF"

echo "✅ Provenance attested"
echo ""

# Step 5: Verify attestations were created
echo "Step 5: Verifying attestations..."
cosign tree "$IMAGE_REF" || echo "Warning: Could not display attestation tree"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "Attestation Summary"
echo "═══════════════════════════════════════════════════════"
echo "✅ SBOM attached: $SBOM_FILE"
echo "✅ Provenance attested: $PROVENANCE_FILE"
echo ""
echo "Verification commands:"
echo ""
echo "# Verify SBOM:"
echo "cosign download sbom $IMAGE_REF"
echo ""
echo "# Verify provenance:"
if [ "${COSIGN_EXPERIMENTAL:-0}" = "1" ]; then
  echo "COSIGN_EXPERIMENTAL=1 cosign verify-attestation \\"
  echo "  --type slsaprovenance \\"
  echo "  --certificate-identity <your-identity> \\"
  echo "  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\"
  echo "  $IMAGE_REF | jq '.payload | @base64d | fromjson'"
else
  echo "cosign verify-attestation \\"
  echo "  --key ${COSIGN_KEY:-/path/to/key} \\"
  echo "  --type slsaprovenance \\"
  echo "  $IMAGE_REF | jq '.payload | @base64d | fromjson'"
fi
echo ""
echo "═══════════════════════════════════════════════════════"
