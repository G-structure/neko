# Nix Build Guide

> **⚠️ STATUS: WORK IN PROGRESS**
>
> The Nix build system successfully compiles and packages Neko into Docker images, but the runtime environment is not yet fully functional. Images build successfully but containers fail to start due to path mismatches between Nix's `/nix/store/` layout and the application's FHS expectations.
>
> **See [nix-build-status.md](./nix-build-status.md) for current status, known issues, and fixes applied.**
>
> This guide documents the intended workflow. For production use, continue using traditional Dockerfiles.

This document explains how to build Neko using Nix for deterministic, reproducible builds.

## Prerequisites

### Install Nix

```bash
# Install Nix with flakes enabled
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate systems.com/nix | sh -s -- install

# Or use the official installer with flakes
sh <(curl -L https://nixos.org/nix/install) --daemon

# Enable flakes (if using official installer)
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### Verify Installation

```bash
nix --version
nix flake show github:m1k1o/neko
```

## Building

### Build the Complete Image

```bash
# Build the full OCI image
nix build .#image

# The result will be in ./result
ls -la result/
```

### Build Individual Components

```bash
# Build just the server
nix build .#nekoServer

# Build just the client
nix build .#nekoClient

# Build X.org drivers
nix build .#xorgDeps

# Build runtime environment
nix build .#runtimeEnv
```

### Cross-Platform Builds

```bash
# Build for ARM64 (on x86_64 host)
nix build .#packages.aarch64-linux.image

# Build for x86_64 (explicit)
nix build .#packages.x86_64-linux.image
```

## Reproducibility

### Verify Reproducibility Locally

```bash
# Run the reproducibility check script
./scripts/repro-check.sh

# Or use the flake app
nix run .#check-reproducibility
```

This will:
1. Build the image
2. Rebuild it from scratch
3. Compare NAR hashes
4. Report if the builds are identical

### Expected Output

```
✅ NAR HASHES MATCH!
  Hash: sha256:abc123...
✅ NAR SIZES MATCH!
  Size: 1234567890 bytes
═══════════════════════════════════════
✅ REPRODUCIBILITY CHECK PASSED!
═══════════════════════════════════════
```

## Development

### Enter Development Shell

```bash
# Enter a shell with all build tools
nix develop

# Now you have access to:
# - go, nodejs, python
# - nix tools (nil, nixpkgs-fmt)
# - container tools (skopeo, crane, cosign)
# - All build dependencies
```

### Rebuild Components

```bash
# In the dev shell
cd server && ./build
cd client && npm run build
```

### Update Dependencies

#### Update Flake Inputs

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Check what changed
nix flake metadata
```

#### Update Go Dependencies

```bash
cd server
go get -u ./...
go mod tidy

# Rebuild to get new vendorHash
nix build .#nekoServer 2>&1 | grep "got:"
# Copy the hash and update nix/server.nix
```

#### Update npm Dependencies

```bash
cd client
npm update

# Rebuild to get new npmDepsHash
nix build .#nekoClient 2>&1 | grep "got:"
# Copy the hash and update nix/client.nix
```

## Caching

### Use Binary Cache

The Nix builds can be cached for faster rebuilds:

```bash
# Using magic-nix-cache (GitHub Actions)
# Automatically configured in CI

# Using Cachix
cachix use neko  # If available

# Using custom cache
nix build .#image \
  --substituters https://cache.example.com \
  --trusted-public-keys cache.example.com-1:abc123...
```

### Push to Cache

```bash
# Push build results to Cachix
nix build .#image
cachix push neko ./result

# Push to custom S3 cache
nix copy --to s3://my-bucket?region=us-east-1 .#image
```

## Troubleshooting

### Build Fails with "hash mismatch"

This means the vendorHash or npmDepsHash needs updating:

```bash
# For Go (server)
nix build .#nekoServer 2>&1 | grep "got:"
# Update vendorHash in nix/server.nix

# For npm (client)
nix build .#nekoClient 2>&1 | grep "got:"
# Update npmDepsHash in nix/client.nix
```

### Garbage Collection

Nix builds can take up disk space:

```bash
# Remove old build results
nix-collect-garbage

# Remove old generations (more aggressive)
nix-collect-garbage -d

# Remove everything not currently used
nix store gc
```

### Clear Build Cache

```bash
# Remove all cached builds
nix store delete $(nix-store -q --outputs .#image)

# Force rebuild
nix build .#image --rebuild
```

## Advanced

### Inspect Build Outputs

```bash
# Show NAR hash and size
nix path-info --json .#image | jq

# Show all dependencies
nix-store -q --tree ./result

# Show closure size
nix path-info -S .#image
```

### Debug Builds

```bash
# Build with verbose output
nix build .#image -L

# Drop into build environment
nix develop .#nekoServer

# Inspect derivation
nix show-derivation .#image
```

### Modify Build Parameters

You can override build parameters:

```bash
# Override version
nix build .#image --override-input version "2.6.0"

# Use different nixpkgs
nix build .#image --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
```

## CI/CD Integration

See `.github/workflows/nix-build-sign.yml` for the complete CI pipeline.

Key steps:
1. Install Nix with flakes
2. Setup magic-nix-cache for speed
3. Build with `nix build`
4. Check reproducibility
5. Push to registry
6. Sign with cosign
7. Attest provenance + SBOM

## Next Steps

- [Verify Artifacts](verify-artifacts.md) - Verify signatures and attestations
- [Release Process](release-process.md) - Cut a new release
