# Release Process

This document describes how to cut a new release of Neko with deterministic builds and cryptographic attestation.

## Overview

A Neko release includes:
1. **OCI image** - Multi-platform container image
2. **Signatures** - Cosign signatures (keyless via Sigstore)
3. **Provenance** - SLSA build provenance attestation
4. **SBOM** - Software Bill of Materials
5. **Release manifest** - NAR hash ↔ OCI digest mapping
6. **GitHub release** - Release notes + artifacts

## Prerequisites

- [ ] Maintainer access to the repository
- [ ] All tests passing on `master`
- [ ] CHANGELOG.md updated
- [ ] No known critical bugs

## Release Steps

### 1. Prepare Release Branch (Optional)

For major releases, create a release branch:

```bash
git checkout -b release/v2.6.0
```

### 2. Update Version Numbers

Update version in:
- `client/package.json`
- `server/version.go` (if exists)
- `CHANGELOG.md`

```bash
# Example for client
cd client
npm version 2.6.0 --no-git-tag-version
```

### 3. Commit Version Bump

```bash
git add client/package.json CHANGELOG.md
git commit -m "chore: bump version to 2.6.0"
git push origin master
# or: git push origin release/v2.6.0
```

### 4. Create Git Tag

```bash
# Create annotated tag
git tag -a v2.6.0 -m "Release v2.6.0"

# Push tag to trigger CI
git push origin v2.6.0
```

### 5. CI Automatically Builds and Signs

GitHub Actions will automatically:
1. ✅ Build image with Nix
2. ✅ Verify reproducibility
3. ✅ Push to `ghcr.io/m1k1o/neko/base:2.6.0`
4. ✅ Sign with cosign (keyless)
5. ✅ Attach provenance and SBOM
6. ✅ Generate release manifest
7. ✅ Create GitHub release with artifacts

Monitor at: `https://github.com/m1k1o/neko/actions`

### 6. Verify Release Artifacts

Once CI completes:

```bash
# Get image digest from CI output or registry
IMAGE_DIGEST="sha256:abc123..."
IMAGE_REF="ghcr.io/m1k1o/neko/base:2.6.0"

# Verify signature
COSIGN_EXPERIMENTAL=1 cosign verify \
  --certificate-identity "https://github.com/m1k1o/neko/.github/workflows/nix-build-sign.yml@refs/tags/v2.6.0" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$IMAGE_REF@$IMAGE_DIGEST"

# Verify provenance
COSIGN_EXPERIMENTAL=1 cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity "https://github.com/m1k1o/neko/.github/workflows/nix-build-sign.yml@refs/tags/v2.6.0" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$IMAGE_REF@$IMAGE_DIGEST"

# Check SBOM
cosign download sbom "$IMAGE_REF@$IMAGE_DIGEST"
```

### 7. Test Release Image

```bash
# Pull and test
docker pull ghcr.io/m1k1o/neko/base:2.6.0

# Run smoke test
docker run --rm -p 8080:8080 ghcr.io/m1k1o/neko/base:2.6.0
# Access http://localhost:8080
```

### 8. Verify Reproducibility

```bash
# Clone at release tag
git clone https://github.com/m1k1o/neko
cd neko
git checkout v2.6.0

# Download release manifest
curl -sL https://github.com/m1k1o/neko/releases/download/v2.6.0/release-manifest.json \
  > expected-manifest.json

# Get expected NAR hash
EXPECTED_NAR=$(jq -r '.nix.narHash' expected-manifest.json)

# Build locally
nix build .#image

# Get actual NAR hash
ACTUAL_NAR=$(nix path-info --json ./result | jq -r '.[0].narHash')

# Compare
if [ "$EXPECTED_NAR" = "$ACTUAL_NAR" ]; then
  echo "✅ Build is reproducible!"
else
  echo "❌ NAR hashes don't match"
  echo "Expected: $EXPECTED_NAR"
  echo "Actual:   $ACTUAL_NAR"
fi
```

### 9. Update Release Notes

Edit the GitHub release created by CI:

1. Go to `https://github.com/m1k1o/neko/releases/tag/v2.6.0`
2. Click "Edit release"
3. Add highlights and breaking changes from CHANGELOG.md
4. Add verification instructions (see template below)

#### Release Notes Template

```markdown
# Neko v2.6.0

## Highlights
- Feature X
- Performance improvement Y
- Bug fix Z

## Breaking Changes
None

## Verification

This release is cryptographically signed and reproducibly built.

### Verify Signature
\`\`\`bash
COSIGN_EXPERIMENTAL=1 cosign verify \
  --certificate-identity "https://github.com/m1k1o/neko/.github/workflows/nix-build-sign.yml@refs/tags/v2.6.0" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/m1k1o/neko/base:2.6.0
\`\`\`

### Reproduce Build
\`\`\`bash
git clone https://github.com/m1k1o/neko
cd neko && git checkout v2.6.0
nix build .#image
./scripts/repro-check.sh
\`\`\`

Expected NAR hash: `sha256-abc123...` (from release-manifest.json)

## Artifacts
- `release-manifest.json` - NAR hash and OCI digest mapping
- `provenance.json` - SLSA build provenance
- `sbom.spdx.json` - Software Bill of Materials

## Full Changelog
[All changes since v2.5.0](https://github.com/m1k1o/neko/compare/v2.5.0...v2.6.0)
```

### 10. Announce Release

- [ ] Post to GitHub Discussions
- [ ] Update documentation site
- [ ] Tweet/social media announcement (if applicable)
- [ ] Notify key users

## Hotfix Releases

For patch releases (e.g., v2.6.1):

```bash
# Create from release branch
git checkout v2.6.0
git checkout -b release/v2.6.1

# Apply hotfix
git cherry-pick <commit-hash>

# Tag and push
git tag -a v2.6.1 -m "Hotfix release v2.6.1"
git push origin v2.6.1
```

## Rollback

If a release has issues:

### Mark Release as Pre-release

1. Go to GitHub releases
2. Edit the problematic release
3. Check "Set as a pre-release"
4. Add warning to release notes

### Revert Tag

```bash
# Delete tag locally and remotely
git tag -d v2.6.0
git push --delete origin v2.6.0

# Delete GitHub release
gh release delete v2.6.0
```

### Remove Image from Registry

```bash
# Images can't be deleted from GHCR, but you can untag
# Recommend creating a new patch release instead
```

## Post-Release Checklist

- [ ] Verify signature and provenance
- [ ] Test reproducibility
- [ ] Update documentation
- [ ] Update release notes
- [ ] Announce release
- [ ] Monitor for issues

## Troubleshooting

### CI Build Fails

1. Check GitHub Actions logs
2. If Nix build fails, test locally:
   ```bash
   nix build .#image -L
   ```
3. If reproducibility check fails, investigate with:
   ```bash
   ./scripts/repro-check.sh
   diffoscope result1/ result2/
   ```

### Signature Creation Fails

1. Check OIDC token permissions in workflow
2. Verify `id-token: write` permission is set
3. Check cosign logs for auth errors

### Attestation Missing

1. Check if `attest-image.sh` ran successfully
2. Verify with: `cosign tree $IMAGE_REF`
3. Re-run attestation manually if needed

## Security Considerations

### Signing Key Rotation

We use keyless signing (OIDC), so there are no long-lived keys to rotate.

Signatures are tied to:
- GitHub Actions OIDC identity
- Specific workflow file path
- Git ref (tag/branch)

### TDX/TEE Signing (Optional)

For TEE-gated signing, set in CI:

```yaml
env:
  TDX_ENABLED: "1"
  TDX_PROVIDER: "azure-akv"  # or gcp-kms, hashicorp-vault
```

See `scripts/attested-key` for implementation.

## References

- [Nix Build Guide](nix-build.md)
- [Artifact Verification](verify-artifacts.md)
- [Semantic Versioning](https://semver.org/)
- [SLSA Specification](https://slsa.dev/)
