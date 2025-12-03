{
  description = "Neko - Self-hosted virtual browser with deterministic builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ... }:
    let
      # Helper function to build Neko for a specific Linux target system
      # Can be called from any build platform (darwin or linux)
      mkNekoPackages = targetSystem: buildSystem:
        let
          pkgs = import nixpkgs {
            system = targetSystem;
            config = {};
            overlays = [
              # Use Go 1.24 and libxcvt from unstable
              (final: prev: {
                go_1_24 = nixpkgs-unstable.legacyPackages.${targetSystem}.go_1_24 or nixpkgs-unstable.legacyPackages.${targetSystem}.go;
                libxcvt = nixpkgs-unstable.legacyPackages.${targetSystem}.libxcvt;
              })
            ];
          };

          # Import version info from git
          versionInfo = import ./nix/lib/version.nix {
            inherit (pkgs) lib;
            src = self;
          };

          # Common args for all derivations
          commonArgs = {
            inherit (versionInfo) version gitCommit gitBranch gitTag SOURCE_DATE_EPOCH;
            inherit pkgs;
            buildPkgs = pkgs;
          };

          # Build components
          nekoServer = pkgs.callPackage ./nix/server.nix commonArgs;
          nekoClient = pkgs.callPackage ./nix/client.nix commonArgs;
          xorgDeps = pkgs.callPackage ./nix/xorg-deps.nix commonArgs;
          runtimeEnv = pkgs.callPackage ./nix/runtime.nix commonArgs;

          # OCI image (base)
          image = pkgs.callPackage ./nix/image.nix {
            inherit nekoServer nekoClient xorgDeps runtimeEnv;
            inherit (commonArgs) version SOURCE_DATE_EPOCH;
          };

          # Chromium app image (complete standalone image with chromium)
          chromiumImage = pkgs.callPackage ./nix/chromium-image.nix {
            inherit nekoServer nekoClient xorgDeps runtimeEnv;
            inherit (commonArgs) version SOURCE_DATE_EPOCH;
          };

          # SBOM generation
          sbom = pkgs.callPackage ./sbom/sbomnix.nix {
            inherit nekoServer nekoClient xorgDeps image;
          };

          # Provenance generation (SLSA format)
          provenance = pkgs.writeTextFile {
            name = "neko-provenance.json";
            text = builtins.toJSON {
                _type = "https://in-toto.io/Statement/v0.1";
                predicateType = "https://slsa.dev/provenance/v1";
                subject = [{
                  name = "ghcr.io/m1k1o/neko/base";
                  digest = {
                    sha256 = image.imageDigest or "pending";
                  };
                }];
                predicate = {
                  buildDefinition = {
                    buildType = "https://nix.dev/nixos/flake-build@v1";
                    externalParameters = {
                      repository = "https://github.com/m1k1o/neko";
                      ref = versionInfo.gitBranch;
                      commit = versionInfo.gitCommit;
                    };
                    resolvedDependencies = [
                      {
                        uri = "pkg:nix/nixpkgs@${nixpkgs.rev}";
                        digest.sha256 = nixpkgs.narHash;
                      }
                    ];
                  };
                  runDetails = {
                    builder.id = "https://github.com/NixOS/nix/releases/tag/2.18.0";
                    metadata = {
                      invocationId = versionInfo.gitCommit;
                      startedOn = builtins.toString versionInfo.SOURCE_DATE_EPOCH;
                    };
                  };
                };
            };
          };

          # Push script
          pushImage = pkgs.writeShellApplication {
            name = "push-neko-image";
            runtimeInputs = [ pkgs.skopeo pkgs.jq ];
            text = ''
                set -euo pipefail

                TAG="''${1:-latest}"
                REGISTRY="''${2:-ghcr.io/m1k1o/neko}"

                echo "Pushing image to $REGISTRY/base:$TAG"

                # Copy image to registry
                ${image.copyToRegistry} "$REGISTRY/base:$TAG"

                # Get manifest digest
                DIGEST=$(skopeo inspect "docker://$REGISTRY/base:$TAG" | jq -r .Digest)
                echo "Image digest: $DIGEST"
                echo "$DIGEST" > image-digest.txt
            '';
          };

        in {
          # Main outputs
          inherit nekoServer nekoClient xorgDeps runtimeEnv image chromiumImage;

          # Utilities
          inherit sbom provenance pushImage;

          # Default package
          default = image;
        };

    in flake-utils.lib.eachDefaultSystem (buildSystem:
      let
        # Build packages for the current build system (for dev tools)
        hostPkgs = nixpkgs.legacyPackages.${buildSystem};
      in {
        # Packages for Linux target systems (Docker images must be Linux)
        packages = {
          # Base images (no browser)
          # x86_64-linux image (Intel/AMD)
          image-x86_64 = (mkNekoPackages "x86_64-linux" buildSystem).image;

          # aarch64-linux image (ARM64)
          image-aarch64 = (mkNekoPackages "aarch64-linux" buildSystem).image;

          # Chromium images (base + chromium browser)
          chromium-x86_64 = (mkNekoPackages "x86_64-linux" buildSystem).chromiumImage;
          chromium-aarch64 = (mkNekoPackages "aarch64-linux" buildSystem).chromiumImage;

          # Default to x86_64 chromium for easy usage
          chromium = (mkNekoPackages "x86_64-linux" buildSystem).chromiumImage;

          # Base image default (backward compatibility)
          image = (mkNekoPackages "x86_64-linux" buildSystem).image;
          default = (mkNekoPackages "x86_64-linux" buildSystem).chromiumImage;

          # Expose all components for x86_64-linux
          nekoServer = (mkNekoPackages "x86_64-linux" buildSystem).nekoServer;
          nekoClient = (mkNekoPackages "x86_64-linux" buildSystem).nekoClient;
          xorgDeps = (mkNekoPackages "x86_64-linux" buildSystem).xorgDeps;
          runtimeEnv = (mkNekoPackages "x86_64-linux" buildSystem).runtimeEnv;
          sbom = (mkNekoPackages "x86_64-linux" buildSystem).sbom;
          provenance = (mkNekoPackages "x86_64-linux" buildSystem).provenance;
          pushImage = (mkNekoPackages "x86_64-linux" buildSystem).pushImage;
        };

      # Development shell (uses host system packages for dev tools)
      devShells.default = hostPkgs.mkShell {
        buildInputs = with hostPkgs; [
            # Nix tools
            nil nixpkgs-fmt nix-tree

            # Container tools
            skopeo crane cosign

            # SBOM/attestation tools
            syft
        ] ++ (if hostPkgs.stdenv.isLinux then [
            # Build tools (only needed on Linux for native builds)
            go_1_24 nodejs_20
            pkg-config
            xorg.libX11 xorg.libXrandr xorg.libXtst
            gtk3 gst_all_1.gstreamer gst_all_1.gst-plugins-base
            supervisor pulseaudio dbus
        ] else []);

        shellHook = ''
            echo "Neko development environment"
            echo ""
            echo "Build commands:"
            echo "  Base images (no browser):"
            echo "    nix build .#image           - Build x86_64-linux base image"
            echo "    nix build .#image-x86_64    - Build x86_64-linux base image"
            echo "    nix build .#image-aarch64   - Build aarch64-linux base image (ARM64)"
            echo ""
            echo "  Chromium images (complete, ready to use):"
            echo "    nix build .#chromium        - Build x86_64-linux chromium image (default)"
            echo "    nix build .#chromium-x86_64 - Build x86_64-linux chromium image"
            echo "    nix build .#chromium-aarch64- Build aarch64-linux chromium image"
            echo ""
            echo "  Components:"
            echo "    nix build .#nekoServer      - Build server binary"
            echo "    nix build .#nekoClient      - Build client dist"
            echo ""
            echo "  Utilities:"
            echo "    nix run .#pushImage         - Push image to registry"
            echo ""
            ${if hostPkgs.stdenv.isDarwin then ''
            echo "📝 Note: Building on macOS requires a Linux builder"
            echo "   You have two options:"
            echo ""
            echo "   1. Use nix-darwin's built-in linux-builder:"
            echo "      Add to your nix-darwin configuration:"
            echo "        nix.linux-builder.enable = true;"
            echo "        nix.settings.trusted-users = [\"@admin\"];"
            echo ""
            echo "   2. Use a remote builder (configured in /etc/nix/machines)"
            echo ""
            echo "   Then build with:"
            echo "      nix build .#image --builders 'linux-builder x86_64-linux /etc/nix/builder_ed25519'"
            echo ""
            '' else ""}
            echo "Current build system: ${buildSystem}"
        '';
      };

      # CI outputs (for GitHub Actions)
      apps = {
        # Build and check reproducibility
        check-reproducibility = {
          type = "app";
          program = toString (hostPkgs.writeShellScript "check-repro" ''
              set -euo pipefail
              echo "Building image..."
              nix build .#image

              echo "Rebuilding to verify reproducibility..."
              nix build .#image --check --rebuild

              echo "✅ Build is reproducible!"

              # Show NAR hash
              nix path-info --json .#image | ${hostPkgs.jq}/bin/jq '.[0] | {narHash, narSize}'
          '');
        };

        # Generate manifest (NAR hash + OCI digest)
        generate-manifest = {
          type = "app";
          program = toString (hostPkgs.writeShellScript "generate-manifest" ''
            ${hostPkgs.python3}/bin/python3 ${./scripts/publish-manifest.py}
          '');
        };
      };
    });

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # For macOS users: Configure linux-builder for building Linux Docker images
    # To enable, add to your nix-darwin configuration:
    #   nix.linux-builder.enable = true;
    #   nix.settings.trusted-users = ["@admin"];
  };
}
