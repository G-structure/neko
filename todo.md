We intend to use the Neko base Docker image `ghcr.io/m1k1o/neko/base:latest`, built from this repository, in an attested production environment. Our goal is to prove to users that the software we claim to run is exactly what is running—no blind trust required—by enabling end-to-end cryptographic verification anchored in an agreed-upon root of trust.

To achieve this, the image must be bit-for-bit reproducible so independent builds are cryptographically identical and verifiable. Unfortunately, naive or ad hoc Dockerfile workflows rarely yield reproducible images, which means you generally cannot prove that two builds are identical.

We should first verify if the Docker image for `ghcr.io/m1k1o/neko/base:latest` is deterministic and reproducible.

Why Docker builds are not reproducible by default
- Moving inputs:
  - Base image tags (for example, :latest) drift; even minor tags can be repushed.
  - Package repositories change over time; mirrors and metadata rotate.
  - External URLs can return different content or fail without notice.
- Nondeterministic metadata:
  - File mtimes/ctimes, ownership (UID/GID), xattrs, and file ordering within layers vary.
  - gzip/tar headers (mtimes, names, OS fields) and compression settings change digests.
  - Image config defaults (created timestamp, history, author) are set to “now.”
- Environment/toolchain variance:
  - Different Docker/BuildKit versions, locales, timezones, and host kernels leak into builds.
  - Compilers and linkers may embed timestamps, build paths, or random seeds unless configured.
- Network during build:
  - apt/yum/apk without snapshotting; curl/wget without checksums; content negotiated by geography.
- Multi-arch specifics:
  - QEMU vs native builds, cross-compile vs native toolchains, and CPU feature flags can diverge outputs.

How to make container images reproducible
- Pin and lock all inputs:
  - Reference base images by digest (FROM image@sha256:...).
  - Lock packages to exact versions and use repository snapshots where possible.
  - Pin external downloads by cryptographic hash (and signature when available).
- Normalize timestamps and metadata:
  - Set SOURCE_DATE_EPOCH to a stable value and use tools that honor it.
  - Enforce explicit ownership/permissions; avoid inheriting host defaults and umask.
  - Ensure deterministic file ordering (sort inputs) and stable layer boundaries.
  - Use deterministic compression and metadata: fixed gzip settings and zeroed mtimes.
- Make builds hermetic:
  - Disable network access during the build proper; prefetch or vendor dependencies.
  - Avoid embedding the current time, hostnames, or nondeterministic paths in artifacts.
- Use reproducibility-oriented tooling and settings:
  - Enable BuildKit and fix its behavior/version; prefer reproducible flags (for example, disable auto SBOM/provenance if they vary).
  - Consider Nix (nix2container/dockerTools), apko/melange (Wolfi/Chainguard), Bazel rules_oci/rules_docker, or pipelines that canonicalize OCI metadata and compression.
- Verify determinism:
  - Perform two clean builds from the same commit on different machines and compare the config and all layer digests.
  - Compare exported images (for example, docker save or crane export) with byte-for-byte checksums.
  - Repeat after cache eviction and at a later date to ensure stability over time.

We agentically explored the build process for the Neko Docker images and determined if they are bit-for-bit reproducible. We documented our findings in a new markdown document in the project root titled "bit4bit.md".

Nix gives us a hermetic, pinned build environment that makes bit-for-bit reproducibility achievable and testable. When the package and image recipes are written to be reproducible, independent rebuilds can produce identical artifacts whose digests match. We will enforce this with reproducibility checks and published digests to support TEE attestation.
