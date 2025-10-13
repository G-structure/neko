# Artifact Verification Guide

This guide shows you how to verify Neko images, signatures, attestations, and reproducibility.

## Why Verify?

Verification ensures:
- **Authenticity**: The image was built by the Neko project
- **Integrity**: The image hasn't been tampered with
- **Reproducibility**: The image can be rebuilt to match exactly
- **Provenance**: You can trace the build back to source code

## Prerequisites

### Install Tools

```bash
# Install cosign
nix-shell -p cosign

# Or use the installer
curl -sSfL https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 \
  -o /usr/local/bin/cosign
chmod +x /usr/local/bin/cosign

# Install other tools
nix-shell -p skopeo jq
```

## Quick Verification

### Using the Verification Script

```bash
# Clone the repo
git clone https://github.com/m1k1o/neko
cd neko

# Verify an image
COSIGN_EXPERIMENTAL=1 \
COSIGN_IDENTITY=github-actions@users.noreply.github.com \
  ./scripts/verify-image.sh ghcr.io/m1k1o/neko/base@sha256:abc123...
```

Expected output:
```
✅ Signature verified (keyless)
✅ SBOM found (X packages)
✅ SLSA provenance attestation verified
✅ Image digest matches reference
═══════════════════════════════════════
✅ VERIFICATION PASSED
═══════════════════════════════════════
```

## Step-by-Step Verification

### 1. Verify Image Signature

#### Keyless Verification (GitHub Actions)

```bash
IMAGE="ghcr.io/m1k1o/neko/base@sha256:abc123..."

COSIGN_EXPERIMENTAL=1 cosign verify \
  --certificate-identity "https://github.com/m1k1o/neko/.github/workflows/nix-build-sign.yml@refs/heads/master" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$IMAGE"
```

#### Key-Based Verification

If a public key is published:

```bash
cosign verify \
  --key /path/to/neko-cosign.pub \
  "$IMAGE"
```

### 2. Verify SLSA Provenance

```bash
IMAGE="ghcr.io/m1k1o/neko/base@sha256:abc123..."

# Download and verify provenance
COSIGN_EXPERIMENTAL=1 cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity "https://github.com/m1k1o/neko/.github/workflows/nix-build-sign.yml@refs/heads/master" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$IMAGE" | \
  jq -r '.payload | @base64d | fromjson'
```

Inspect provenance fields:
```bash
# ... | jq '.predicate.buildDefinition'
{
  "buildType": "https://nix.dev/flake-build@v1",
  "externalParameters": {
    "repository": "https://github.com/m1k1o/neko",
    "ref": "master",
    "commit": "abc123..."
  },
  "internalParameters": {
    "narHash": "sha256-xyz..."
  }
}
```

### 3. Download and Inspect SBOM

```bash
IMAGE="ghcr.io/m1k1o/neko/base@sha256:abc123..."

# Download SBOM
cosign download sbom "$IMAGE" > neko-sbom.spdx.json

# Inspect SBOM
jq '.packages | length' neko-sbom.spdx.json
jq '.packages[] | select(.name == "gstreamer")' neko-sbom.spdx.json
```

### 4. Verify Reproducibility

#### Compare NAR Hash

From the release manifest:

```bash
# Download release manifest
curl -sL https://github.com/m1k1o/neko/releases/download/v2.5.0/release-manifest.json \
  > manifest.json

# Get NAR hash
jq -r '.nix.narHash' manifest.json
# Output: sha256-abc123...

# Rebuild locally and compare
git clone https://github.com/m1k1o/neko
cd neko
git checkout v2.5.0

nix build .#image
nix path-info --json ./result | jq -r '.[0].narHash'
# Output should match: sha256-abc123...
```

#### Full Reproducibility Check

```bash
# Clone at specific commit
git clone https://github.com/m1k1o/neko
cd neko
git checkout abc123...  # commit from provenance

# Run reproducibility check
./scripts/repro-check.sh
```

## Verification in Production

### Kubernetes Admission Controllers

#### Using Policy Controller (Sigstore)

```bash
# Install policy-controller
kubectl apply -f https://github.com/sigstore/policy-controller/releases/latest/download/policy-controller.yaml

# Apply Neko image policy
kubectl apply -f policy/cluster/sigstore-policy.yaml
```

Now, any pod using `ghcr.io/m1k1o/neko/**` images will be automatically verified.

#### Using Kyverno

```bash
# Install Kyverno
kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml

# Apply policy from our repo
kubectl apply -f policy/cluster/sigstore-policy.yaml
```

### Docker Content Trust Alternative

While we use Cosign, you can also verify with:

```bash
# Enable content trust
export DOCKER_CONTENT_TRUST=1

# Pull will fail if signature is invalid
docker pull ghcr.io/m1k1o/neko/base:latest
```

## Verification Checklist

For production deployments, verify:

- [ ] **Signature exists and is valid**
  ```bash
  COSIGN_EXPERIMENTAL=1 cosign verify "$IMAGE"
  ```

- [ ] **Provenance exists and matches repository**
  ```bash
  COSIGN_EXPERIMENTAL=1 cosign verify-attestation \
    --type slsaprovenance "$IMAGE" | \
    jq '.payload | @base64d | fromjson | .predicate.buildDefinition.externalParameters.repository'
  # Should output: "https://github.com/m1k1o/neko"
  ```

- [ ] **SBOM is attached**
  ```bash
  cosign download sbom "$IMAGE" | jq '.packages | length'
  ```

- [ ] **NAR hash matches release manifest**
  ```bash
  # Compare local build with published manifest
  ```

- [ ] **Image digest is used (not tag)**
  ```bash
  # Always use: ghcr.io/m1k1o/neko/base@sha256:...
  # Never use: ghcr.io/m1k1o/neko/base:latest
  ```

## Troubleshooting

### "no matching signatures found"

- Check you're using `COSIGN_EXPERIMENTAL=1` for keyless
- Ensure you're using the correct OIDC identity and issuer
- Verify image reference includes `@sha256:...` digest

### "provenance not found"

- Image may not have attestations (old build)
- Check with: `cosign tree "$IMAGE"`

### "NAR hash mismatch"

- You may be at a different git commit
- Ensure you're checking out the exact commit from provenance
- Check that flake.lock hasn't changed

### "SBOM is empty"

- SBOM generation may have failed in CI
- Check GitHub Actions logs
- Regenerate with: `./scripts/attest-image.sh "$IMAGE"`

## Automation

### CI/CD Integration

Add verification to your deployment pipeline:

```yaml
# .github/workflows/deploy.yml
- name: Verify image
  env:
    COSIGN_EXPERIMENTAL: "1"
    IMAGE: ghcr.io/m1k1o/neko/base@sha256:${{ needs.build.outputs.digest }}
  run: |
    ./scripts/verify-image.sh "$IMAGE"
```

### Pre-commit Hook

```bash
# .git/hooks/pre-push
#!/bin/bash
# Verify latest image before deploying

IMAGE="ghcr.io/m1k1o/neko/base:edge"
./scripts/verify-image.sh "$IMAGE" || exit 1
```

## Learn More

- [Sigstore Documentation](https://docs.sigstore.dev/)
- [SLSA Provenance Spec](https://slsa.dev/provenance/v1)
- [Cosign CLI Reference](https://docs.sigstore.dev/cosign/overview/)
- [Nix Build Guide](nix-build.md)
- [Release Process](release-process.md)
