# Bit-for-Bit Reproducibility Analysis: Neko Base Docker Image

**Date:** 2025-10-04
**Image:** `ghcr.io/m1k1o/neko/base:latest`
**Status:** ❌ **NOT REPRODUCIBLE**

## Executive Summary

The Neko base Docker image build process is **not bit-for-bit reproducible**. Independent builds of the same source will produce cryptographically different images due to multiple sources of non-determinism in the build pipeline. This prevents end-to-end cryptographic verification and attestation in production environments.

## Critical Reproducibility Issues

### 1. Base Images Not Pinned by Digest ❌

All base images use mutable tags instead of immutable digests:

| Dockerfile | Base Image | Issue |
|------------|------------|-------|
| `server/Dockerfile:1` | `golang:1.24-bullseye` | Tag can point to different images over time |
| `client/Dockerfile:1` | `node:18-bullseye-slim` | Tag can point to different images over time |
| `runtime/Dockerfile:1` | `debian:bullseye-slim` | Tag can point to different images over time |
| `runtime/Dockerfile.bookworm:1` | `debian:bookworm-slim` | Tag can point to different images over time |
| `runtime/Dockerfile.nvidia:9` | `ubuntu:${UBUNTU_RELEASE}` | Tag can point to different images over time |
| `runtime/Dockerfile.nvidia:59` | `nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_RELEASE}` | Tag can point to different images over time |
| `utils/xorg-deps/Dockerfile:1` | `debian:bullseye-slim` | Tag can point to different images over time |
| `build:321` | `golang:1.24-bullseye` | Used by template processor |

**Impact:** The foundation of every build is non-deterministic. Even if all other issues were fixed, using mutable base image tags means two builds could start from different base layers.

**Fix Required:** Pin all base images by SHA256 digest:
```dockerfile
FROM debian:bullseye-slim@sha256:a165446a88794db4fec31e35e9441433f9552ae048fb1ed26df352d2b537cb96
```

### 2. Build Timestamp Embedded in Binary ❌

**Location:** `server/build:33`

```bash
go build \
    -ldflags "
        -s -w
        -X 'm1k1o/neko.buildDate=`date -u +'%Y-%m-%dT%H:%M:%SZ'`'
        ...
    " \
    cmd/neko/main.go
```

**Impact:** Every build embeds the current timestamp into the server binary, making it impossible to produce identical binaries from the same source.

**Fix Required:**
1. Use `SOURCE_DATE_EPOCH` environment variable instead of `date`:
   ```bash
   -X 'm1k1o/neko.buildDate=${SOURCE_DATE_EPOCH:-$(date -u +'%Y-%m-%dT%H:%M:%SZ')}'
   ```
2. Set `SOURCE_DATE_EPOCH` to git commit timestamp or a fixed value in the build script

### 3. Package Versions Not Pinned ❌

**All Dockerfiles** install packages without version pinning:

```dockerfile
# runtime/Dockerfile:14-15
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        wget ca-certificates python2 supervisor \
        pulseaudio dbus-x11 xserver-xorg-video-dummy \
        ...
```

**Impact:** Package versions change over time in Debian/Ubuntu repositories. Builds at different times will install different package versions, leading to different binaries and different layer hashes.

**Examples across codebase:**
- `runtime/Dockerfile:14-76` - 30+ packages unpinned
- `runtime/Dockerfile.nvidia:15-40` - Build dependencies unpinned
- `runtime/Dockerfile.nvidia:125-184` - Runtime dependencies unpinned
- `server/Dockerfile:10-13` - Build libraries unpinned
- `client/Dockerfile:9` - `npm install` (uses package-lock.json, which is good)
- `runtime/Dockerfile.nvidia:36` - `pip3 install meson` unpinned

**Fix Required:**
1. Generate a lockfile of exact package versions from a reference build
2. Use `apt-get install package=version` syntax for all packages
3. Consider using tools like `apt-snapshot` or vendoring .deb files

### 4. External Downloads Without Hash Verification ❌

#### libxcvt Library Downloads

**Locations:**
- `runtime/Dockerfile:33-35`
- `runtime/Dockerfile.nvidia:140-143`
- `server/Dockerfile:17-20`

```dockerfile
ARCH=$(dpkg --print-architecture); \
wget http://ftp.de.debian.org/debian/pool/main/libx/libxcvt/libxcvt0_0.1.2-1_${ARCH}.deb; \
apt-get install --no-install-recommends ./libxcvt0_0.1.2-1_${ARCH}.deb; \
rm ./libxcvt0_0.1.2-1_${ARCH}.deb;
```

**Impact:** Files downloaded without checksum verification. If the file on the mirror changes or is compromised, builds will differ or be malicious.

#### GStreamer Git Clone

**Location:** `runtime/Dockerfile.nvidia:45`

```dockerfile
git clone --depth 1 --branch $GSTREAMER_VERSION https://gitlab.freedesktop.org/gstreamer/gstreamer.git /gstreamer/src;
```

**Impact:** Branch tags can move to different commits. Even `--branch 1.20` is not a commit hash, so different builds may clone different code.

#### VirtualGL Repository

**Location:** `runtime/Dockerfile.nvidia:212-219`

```dockerfile
wget -q -O- https://packagecloud.io/dcommander/virtualgl/gpgkey | \
gpg --dearmor >/etc/apt/trusted.gpg.d/VirtualGL.gpg; \
wget -q -O /etc/apt/sources.list.d/VirtualGL.list \
    https://raw.githubusercontent.com/VirtualGL/repo/main/VirtualGL.list;
apt-get update; \
apt-get install -y --no-install-recommends virtualgl=${VIRTUALGL_VERSION};
```

**Impact:**
- GPG key downloaded without verification
- Repository list downloaded from GitHub `main` branch (mutable)
- VirtualGL version is pinned (good), but repository metadata is not

**Fix Required:**
1. Verify all downloads with SHA256 checksums:
   ```dockerfile
   wget http://example.com/file.deb && \
   echo "expected_sha256  file.deb" | sha256sum -c -
   ```
2. Pin git clones to specific commit hashes:
   ```dockerfile
   git clone https://gitlab.freedesktop.org/gstreamer/gstreamer.git /gstreamer/src && \
   cd /gstreamer/src && \
   git checkout <commit-hash>
   ```
3. Vendor external files in the repository

### 5. Missing BuildKit Reproducibility Flags ❌

**Location:** `build:161-165`, `build:197-200`

The build script does not use BuildKit's reproducibility features:

```bash
docker build \
  --platform $PLATFORM \
  $NO_CACHE \
  -t $APPLICATION_IMAGE \
  $@
```

**Missing flags:**
- `SOURCE_DATE_EPOCH` environment variable not set
- No `--build-arg SOURCE_DATE_EPOCH=...`
- No use of `--output type=oci` for standardized output
- BuildKit experimental reproducibility features not enabled

**Impact:** Docker layer metadata (timestamps, ordering) may vary between builds.

**Fix Required:**
```bash
# Set SOURCE_DATE_EPOCH to last git commit timestamp
export SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct)

docker build \
  --build-arg SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH \
  --platform $PLATFORM \
  $NO_CACHE \
  -t $APPLICATION_IMAGE \
  $@
```

### 6. File Ordering and Metadata ⚠️

**Locations:** Multiple COPY commands throughout

Docker COPY commands may not preserve deterministic file ordering or metadata:
- `Dockerfile.tmpl:11-15` - Copying from multi-stage builds
- `runtime/Dockerfile:80-91` - Copying config files and fonts
- `server/Dockerfile:32` - Copying entire source tree

**Impact:** File modification times, ownership, and ordering may vary. While modern BuildKit has improved this, it's not guaranteed without explicit configuration.

**Fix Required:**
1. Use `--chmod` and `--chown` flags in COPY commands for explicit ownership
2. Ensure files are added in a deterministic order
3. Strip file metadata where possible

### 7. npm Dependencies ✅ (Mostly Good)

**Location:** `client/Dockerfile:8-9`

```dockerfile
COPY package*.json ./
RUN npm install
```

**Status:** Partially reproducible. The `package-lock.json` file pins exact dependency versions (good), but:
- npm registry can serve different tarballs for same versions
- npm itself is not version-pinned
- node base image is not digest-pinned

**Recommendation:** Use `npm ci` instead of `npm install` for more reproducible installs.

## Build Process Architecture

The Neko build uses a custom template system:

1. **Template Processing** (`build:316-323`):
   ```bash
   docker run --rm -i \
     -v "$(pwd)":/src \
     -e "RUNTIME_DOCKERFILE=$RUNTIME_DOCKERFILE" \
     --workdir /src \
     --entrypoint go \
     golang:1.24-bullseye \
     run utils/docker/main.go \
     -i Dockerfile.tmpl -client "$CLIENT_DIST"
   ```
   - Runs Go code to process `Dockerfile.tmpl`
   - Merges sub-Dockerfiles (server, client, xorg-deps, runtime)
   - Outputs a single Dockerfile to stdout

2. **Multi-Stage Build Stages:**
   - `server`: Builds Go server binary
   - `client`: Builds Vue.js client dist
   - `xorg-deps`: Compiles Xorg drivers
   - `runtime`: Final runtime environment

Each stage has its own reproducibility issues.

## Severity Assessment

| Issue | Severity | Impact on Reproducibility | Difficulty to Fix |
|-------|----------|---------------------------|-------------------|
| Base images not pinned | **CRITICAL** | Complete non-determinism | Easy |
| Build timestamp in binary | **CRITICAL** | Binary always different | Easy |
| Package versions not pinned | **HIGH** | Layer hashes differ over time | Medium |
| External downloads no hash | **HIGH** | Supply chain risk + non-determinism | Medium |
| Missing SOURCE_DATE_EPOCH | **MEDIUM** | Metadata timestamps differ | Easy |
| File metadata | **LOW** | Minor layer differences | Medium |

## Recommended Fix Priority

### Phase 1: Quick Wins (1-2 hours)

1. **Remove build timestamp** from `server/build:33` or use SOURCE_DATE_EPOCH
2. **Pin base images** to current digests in all Dockerfiles
3. **Add SOURCE_DATE_EPOCH** to build script:
   ```bash
   export SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct)
   ```

### Phase 2: Medium Effort (1-2 days)

4. **Pin all package versions** in Dockerfiles:
   - Generate lockfile from reference build
   - Update all `apt-get install` commands with `package=version`

5. **Add hash verification** for external downloads:
   - libxcvt .deb files
   - VirtualGL GPG key and repo list

6. **Pin git clones** to commit hashes:
   - GStreamer in nvidia Dockerfile

### Phase 3: Advanced (3-5 days)

7. **Consider migration to reproducibility-focused tools:**
   - Nix with `nix2container` or `dockerTools`
   - Apko/Melange (Chainguard/Wolfi)
   - Bazel with `rules_docker`

8. **Implement multi-architecture reproducibility testing:**
   - Build same commit on different machines
   - Compare image digests
   - Automate in CI

9. **Add verification documentation:**
   - Instructions for independent rebuilds
   - Expected image digests for each release
   - Provenance attestation with cosign/in-toto

## Testing Reproducibility

Once fixes are applied, test with:

```bash
# Build 1
./build --tag test1 --yes
IMAGE1=$(docker inspect ghcr.io/m1k1o/neko/base:test1 --format='{{.Id}}')

# Rebuild without cache
docker builder prune -af
./build --tag test2 --yes --no-cache
IMAGE2=$(docker inspect ghcr.io/m1k1o/neko/base:test2 --format='{{.Id}}')

# Compare
if [ "$IMAGE1" = "$IMAGE2" ]; then
    echo "✅ Build is reproducible!"
else
    echo "❌ Build is NOT reproducible"
    echo "Image 1: $IMAGE1"
    echo "Image 2: $IMAGE2"

    # Detailed diff
    docker save ghcr.io/m1k1o/neko/base:test1 | tar -xOf - manifest.json > manifest1.json
    docker save ghcr.io/m1k1o/neko/base:test2 | tar -xOf - manifest.json > manifest2.json
    diff -u manifest1.json manifest2.json
fi
```

## Alternative: Use Reproducibility-First Tools

For production attestation requirements, consider rebuilding with tools designed for reproducibility:

### Option A: Nix + nix2container

```nix
# Super simplified example
pkgs.dockerTools.buildLayeredImage {
  name = "neko";
  tag = "latest";
  contents = [ nekoServer nekoClient xorgDrivers ];
  config = {
    Cmd = [ "/usr/bin/supervisord" "-c" "/etc/neko/supervisord.conf" ];
  };
}
```

**Pros:** Bit-for-bit reproducible by design, content-addressed store
**Cons:** Requires rewriting build logic in Nix

### Option B: Apko (Chainguard/Wolfi)

```yaml
# apko.yaml
contents:
  packages:
    - neko-server@sha256:...
    - pulseaudio@sha256:...
entrypoint:
  command: /usr/bin/supervisord -c /etc/neko/supervisord.conf
```

**Pros:** SBOM generation, small images, reproducible
**Cons:** Limited package ecosystem (Wolfi/Alpine)

### Option C: Bazel + rules_docker

**Pros:** Hermetic builds, content-addressable, proven at scale
**Cons:** Steep learning curve, verbose BUILD files

## Conclusion

The current Neko Docker build is **definitively not bit-for-bit reproducible** due to fundamental issues with mutable inputs, embedded timestamps, and lack of hash verification.

Achieving reproducibility requires:
1. **Immediate fixes:** Pin base images, remove timestamp, add SOURCE_DATE_EPOCH
2. **Medium-term fixes:** Pin packages, verify downloads
3. **Optional long-term:** Migrate to reproducibility-focused build tools

**Estimated effort for basic reproducibility:** 2-4 days
**Estimated effort for production-grade attestation:** 1-2 weeks

## References

- [Reproducible Builds Project](https://reproducible-builds.org/)
- [BuildKit Reproducibility](https://github.com/moby/buildkit/blob/master/docs/build-repro.md)
- [SOURCE_DATE_EPOCH Specification](https://reproducible-builds.org/specs/source-date-epoch/)
- [Nix Docker Tools](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools)
- [Chainguard Apko](https://github.com/chainguard-dev/apko)
