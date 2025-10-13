# Nix Quick Start Guide

Get started with Neko's deterministic, reproducible builds in under 5 minutes.

## Prerequisites

Install Nix with flakes:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate systems.com/nix | sh -s -- install
```

## Quick Start

### 1. Initialize Flake

```bash
# Generate flake.lock (pins all dependencies)
nix flake lock

# Check flake is valid
nix flake check
```

### 2. Update Dependency Hashes

The first build will fail with hash mismatches. This is expected:

```bash
# Build server (will fail with expected hash)
nix build .#nekoServer 2>&1 | tee build.log

# Extract the correct hash
grep "got:" build.log
# Example output: got: sha256-abc123...

# Update nix/server.nix: vendorHash = "sha256-abc123...";
```

Repeat for client:

```bash
nix build .#nekoClient 2>&1 | grep "got:"
# Update nix/client.nix: npmDepsHash = "sha256-xyz...";
```

### 3. Build Everything

```bash
# Build the complete OCI image
nix build .#image

# The result is in ./result
ls -la result/
```

### 4. Verify Reproducibility

```bash
# Run reproducibility check
./scripts/repro-check.sh

# Expected output:
# ✅ NAR HASHES MATCH!
# ✅ REPRODUCIBILITY CHECK PASSED!
```

## Development

### Enter Dev Shell

```bash
nix develop

# Now you have all build tools:
# - go, nodejs, python
# - nix tools
# - container tools (skopeo, cosign)
```

### Build Individual Components

```bash
nix build .#nekoServer    # Go server
nix build .#nekoClient    # Vue client
nix build .#xorgDeps      # X.org drivers
nix build .#runtimeEnv    # System packages
```

### Test Locally

```bash
# Load image to Docker
docker load < result

# Run
docker run --rm -p 8080:8080 ghcr.io/m1k1o/neko/base:2.5.0
```

## Signing & Verification

### Sign an Image

```bash
# Keyless signing (requires GitHub Actions or OIDC)
COSIGN_EXPERIMENTAL=1 ./scripts/sign-image.sh ghcr.io/m1k1o/neko/base:latest

# Key-based signing
COSIGN_KEY=/path/to/key ./scripts/sign-image.sh ghcr.io/m1k1o/neko/base:latest
```

### Verify an Image

```bash
COSIGN_EXPERIMENTAL=1 \
COSIGN_IDENTITY=you@example.com \
  ./scripts/verify-image.sh ghcr.io/m1k1o/neko/base:latest
```

### Generate Attestations

```bash
COSIGN_EXPERIMENTAL=1 ./scripts/attest-image.sh ghcr.io/m1k1o/neko/base:latest

# Creates:
# - provenance.json (SLSA)
# - sbom.spdx.json
```

## CI/CD

### Trigger Build

Push to master or create a tag:

```bash
git tag -a v2.5.1 -m "Release v2.5.1"
git push origin v2.5.1
```

GitHub Actions will automatically:
1. ✅ Build image
2. ✅ Verify reproducibility
3. ✅ Push to GHCR
4. ✅ Sign with cosign
5. ✅ Attach provenance + SBOM
6. ✅ Create release

### Monitor Build

Check progress at:
```
https://github.com/m1k1o/neko/actions
```

## Common Tasks

### Update Dependencies

```bash
# Update flake inputs
nix flake update

# Or update specific input
nix flake lock --update-input nixpkgs
```

### Clean Cache

```bash
# Remove old build results
nix-collect-garbage -d

# Force rebuild
nix build .#image --rebuild
```

### Inspect Build

```bash
# Show NAR hash
nix path-info --json .#image | jq

# Show all dependencies
nix-store -q --tree ./result

# Drop into build shell
nix develop .#nekoServer
```

## Troubleshooting

### "hash mismatch" errors

Update the hash in the Nix file:

```bash
nix build .#nekoServer 2>&1 | grep "got:"
# Copy hash to nix/server.nix vendorHash
```

### "experimental features not enabled"

Enable flakes:

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### Build is slow

Use binary cache:

```bash
nix build .#image --substituters https://cache.nixos.org
```

## Next Steps

- 📖 [Full Build Guide](docs/nix-build.md)
- 🔐 [Verification Guide](docs/verify-artifacts.md)
- 🚀 [Release Process](docs/release-process.md)
- 📋 [Implementation Status](IMPLEMENTATION.md)

## Get Help

- GitHub Issues: https://github.com/m1k1o/neko/issues
- Discord: https://discord.gg/3U6hWpC
- Nix Manual: https://nixos.org/manual/nix/stable/

---

**Quick Links**:
- Verify what you run: See [README](README.md#-verify-what-you-run)
- Report security issues: See [SECURITY.md](SECURITY.md)
