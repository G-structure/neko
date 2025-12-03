# Nix Build Status & Learnings

**Date:** 2025-11-16
**Platform:** macOS (darwin aarch64) with remote x86_64-linux builder

## Summary

Successfully built the Neko base Docker image using Nix, but discovered the runtime environment needs additional work to be fully functional. The existing Nix build infrastructure (`flake.nix`, `nix/*.nix`) appears to be **partially implemented** rather than production-ready.

## Current Status

### ✅ Working
- **Flake structure** - Complete with multi-platform support (x86_64, aarch64)
- **Component builds**:
  - Go server compilation with CGO
  - Vue.js client bundling
  - Custom X.org drivers (dummy_drv, neko input driver)
  - Runtime environment packaging
- **Image creation** - OCI image builds successfully via `dockerTools.buildLayeredImage`
- **Remote building** - Cross-compilation from macOS to Linux via remote builder
- **Image loading** - Built images load into Docker and container starts

### ❌ Not Working
- **Runtime paths** - Binaries in `/nix/store/*` not `/usr/bin/`
- **Supervisord configuration** - Paths hardcoded to `/usr/bin/X`, `/usr/bin/pulseaudio`
- **Temp directory setup** - Neko server crashes on temp file creation
- **No browser included** - Base image has no desktop application (by design, but not functional standalone)

## Issues Fixed

### 1. Go Vendoring Conflict
**Problem:** Build failed with "inconsistent vendoring" errors
```
go: inconsistent vendoring in /build/source:
    github.com/go-vgo/robotgo@v0.110.5: is explicitly required in go.mod,
    but not marked as explicit in vendor/modules.txt
```

**Solution:**
- Set `proxyVendor = true` in `nix/server.nix`
- Excluded `vendor/` directory from source
- Updated `vendorHash` to `sha256-NP5A+h8/ENdliyR+THo6FwnTWRH0JK0b9PmPFROeMik=`

**File:** `nix/server.nix:26-28`

### 2. C Header File Naming
**Problem:** Build failed with "No such file or directory" for C headers
```
drop_linux.c:1:10: fatal error: drop.h: No such file or directory
```

**Root Cause:** C files included `drop.h` but actual headers were `drop_linux.h`

**Solution:** Updated includes in source files:
- `server/pkg/drop/drop_linux.c`
- `server/pkg/xevent/xevent_linux.c`
- `server/pkg/xorg/xorg_linux.c`

Changed from `#include "drop.h"` to `#include "drop_linux.h"`

### 3. Supervisord Configuration Incompatibility
**Problem:** Nix supervisord doesn't support `chown=` directive
```
Error: Invalid sockchown value root:neko
```

**Solution:** Strip unsupported directives during image build

**File:** `nix/image.nix:67-68`
```nix
sed -e '/^chown=/d' -e '/^user=root/d' ${../runtime/supervisord.conf} > $out/etc/neko/supervisord.conf
```

Similarly for `nix/chromium-image.nix:64`

## Remaining Issues

### 1. Binary Path Mismatches

**Problem:** Nix puts binaries in `/nix/store/*/bin/`, not `/usr/bin/`

**Current config expects:**
```
/usr/bin/X
/usr/bin/pulseaudio
/usr/bin/neko
```

**Actual Nix paths:**
```
/nix/store/<hash>-xorg-server-21.1.16/bin/X
/nix/store/<hash>-pulseaudio-17.0/bin/pulseaudio
/nix/store/<hash>-neko-server-2.5.0/bin/neko
```

**Impact:** Supervisor can't start X11, PulseAudio, or Neko server

**Possible solutions:**
1. Create symlinks: `/usr/bin/X` → `/nix/store/*/bin/X`
2. Update supervisord.conf to use Nix store paths directly
3. Create wrapper scripts in `/usr/bin/` that call Nix store binaries
4. Set `PATH` environment variable to include all Nix store bin directories

### 2. Temp Directory Permissions

**Error from Neko server:**
```
assertion failed [!result.is_error]: Failed to create temporary file
(ThreadContextFcntl.cpp:85 create_tempfile)
```

**Likely causes:**
- `/tmp` not writable by `neko` user
- Incorrect ownership/permissions on `/tmp/runtime-neko`
- Missing directories that Neko expects

**Current entrypoint setup:**
```bash
mkdir -p /tmp/runtime-neko
chown $USER_UID:$USER_GID /tmp/runtime-neko
```

This may not be sufficient for all of Neko's temp file needs.

### 3. Missing Runtime Dependencies

The container is missing X11, PulseAudio, and other runtime components in expected locations. The Nix approach bundles everything in `/nix/store/` but the application expects FHS (Filesystem Hierarchy Standard) layout.

## Build Commands

```bash
# Build base image (no browser)
nix build .#image-x86_64

# Build chromium image (with browser)
nix build .#chromium

# Load into Docker
export DOCKER_HOST=unix:///var/run/docker.sock
docker load < result

# Run (will fail at runtime currently)
docker run -p 8080:8080 neko-base:2.5.0
```

## Key Learnings

### 1. Nix vs Traditional Dockerfile Philosophy

**Traditional Dockerfile:**
- Uses base images (Debian, Ubuntu, etc.)
- Installs packages to standard FHS locations (`/usr/bin`, `/etc`, `/var`)
- Relies on system package manager (apt, apk)
- Mutable filesystem

**Nix approach:**
- Everything in `/nix/store/<hash>-package-name/`
- Immutable, content-addressed storage
- No system package manager
- Requires rethinking path assumptions

### 2. The "Impedance Mismatch"

Traditional applications assume FHS layout. Nix applications live in `/nix/store/`. Three approaches to bridge this:

1. **Pure Nix** - Rewrite configs to use Nix store paths (most work, most benefits)
2. **Hybrid** - Symlinks/wrappers to mimic FHS (moderate work, some benefits)
3. **FHS wrapper** - Use `buildFHSUserEnv` to create FHS environment (least work, fewest benefits)

Current implementation attempts #1 (pure Nix) but config files still expect FHS layout (#2).

### 3. Cross-Platform Building

Successfully demonstrated cross-compilation from ARM Mac to x86_64 Linux:
- Used remote builder (EC2 instance)
- Nix handles all cross-compilation complexity
- Built image runs on Mac via Docker's emulation layer

**Note:** Platform warnings are harmless:
```
WARNING: The requested image's platform (linux/amd64) does not match
the detected host platform (linux/arm64/v8)
```

Set `platform: linux/amd64` in docker-compose.yml to suppress.

### 4. Reproducibility Works

Nix's reproducible builds work as advertised:
- Same source + same flake.lock = identical output
- `SOURCE_DATE_EPOCH` ensures deterministic timestamps
- NAR hashes can verify bit-for-bit reproducibility

The `scripts/repro-check.sh` script is present and functional for verification.

### 5. Documentation Status

The docs (`docs/nix-build.md`, `docs/release-process.md`) describe a **planned system**, not current reality:

- ✅ Build infrastructure exists
- ❌ Runtime integration incomplete
- ❌ CI/CD pipeline not functional (references non-existent scripts)
- ❌ No successful end-to-end deployment documented

These docs appear to be "design documents" rather than user guides.

## Recommended Next Steps

### Short-term (Make it work)

1. **Fix runtime paths** - Choose an approach:
   ```nix
   # Option A: Create symlinks in image build
   ln -s /nix/store/*-xorg-server-*/bin/X /usr/bin/X

   # Option B: Generate supervisord.conf with Nix store paths
   substituteInPlace supervisord.conf \
     --replace /usr/bin/X ${xorg-server}/bin/X

   # Option C: Use buildFHSUserEnv
   buildFHSUserEnv {
     name = "neko-env";
     targetPkgs = pkgs: [ xorg-server pulseaudio nekoServer ];
   }
   ```

2. **Fix temp directories** - Add to entrypoint:
   ```bash
   mkdir -p /tmp /var/tmp
   chmod 1777 /tmp /var/tmp
   mkdir -p /tmp/runtime-neko
   chown neko:neko /tmp/runtime-neko
   ```

3. **Test with simplified setup** - Remove supervisord, test components individually:
   ```bash
   docker run -it neko-base:2.5.0 /bin/bash
   # Manually start X, pulseaudio, neko to debug
   ```

### Long-term (Make it maintainable)

1. **Decide on architecture:**
   - Pure Nix paths (requires config rewrite)
   - FHS compatibility layer (easier but less "Nix-y")

2. **Update documentation** to reflect actual state

3. **Add integration tests** to prevent runtime regressions

4. **Consider nix2container** - Modern alternative to `dockerTools`:
   - Faster builds
   - Better layer caching
   - More flexible configuration

## Files Modified

```
nix/server.nix           - Fixed Go vendoring
nix/image.nix           - Fixed supervisord config
nix/chromium-image.nix  - Fixed supervisord config
server/pkg/drop/drop_linux.c     - Fixed C header includes
server/pkg/xevent/xevent_linux.c - Fixed C header includes
server/pkg/xorg/xorg_linux.c     - Fixed C header includes
docker-compose.yaml     - Added platform specification
```

## Useful Resources

- [Nix Docker Tools](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools)
- [nix2container](https://github.com/nlewo/nix2container) - Modern Docker image builder
- [buildFHSUserEnv](https://nixos.org/manual/nixpkgs/stable/#sec-fhs-environments) - FHS compatibility
- [Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer) - What we used

## Conclusion

The Nix build system for Neko is **architecturally sound but incomplete**. We successfully:
- Fixed build-time issues (vendoring, headers, config)
- Generated working OCI images
- Loaded images into Docker

However, runtime environment setup needs significant work before the Nix-built images are functional. This is primarily a path mapping issue - Nix's `/nix/store/` layout conflicts with the application's FHS assumptions.

**Recommendation:** Document this as a "work in progress" feature and either:
1. Invest time to complete the Nix integration (rewrite configs for Nix paths)
2. Use a FHS compatibility layer for quick wins
3. Stick with traditional Dockerfiles for production until Nix approach is proven

The reproducibility and cross-platform benefits of Nix are real, but require full commitment to the Nix paradigm rather than halfway measures.
