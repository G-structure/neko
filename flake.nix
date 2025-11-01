{
  description = "Neko - Self-hosted virtual browser with deterministic builds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ... }:
    let
      # Only support x86_64-linux
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          permittedInsecurePackages = [
            "python-2.7.18.8"  # Required by supervisor
          ];
        };
        overlays = [
          # Use Go 1.24 and libxcvt from unstable
          (final: prev: {
            go_1_24 = nixpkgs-unstable.legacyPackages.${system}.go_1_24 or nixpkgs-unstable.legacyPackages.${system}.go;
            libxcvt = nixpkgs-unstable.legacyPackages.${system}.libxcvt;
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

      # OCI image
      image = pkgs.callPackage ./nix/image.nix {
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
      packages.${system} = {
        # Main outputs
        inherit nekoServer nekoClient xorgDeps runtimeEnv image;

        # Utilities
        inherit sbom provenance pushImage;

        # Default package
        default = image;
      };

      # Development shell
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
            # Nix tools
            nil nixpkgs-fmt nix-tree

            # Build tools
            go_1_24 nodejs_18 python2

            # Server dependencies
            pkg-config
            xorg.libX11 xorg.libXrandr xorg.libXtst
            gtk3 gst_all_1.gstreamer gst_all_1.gst-plugins-base

            # Runtime tools
            supervisor pulseaudio dbus

            # Container tools
            skopeo crane cosign

            # SBOM/attestation tools
            syft sbomnix
        ];

        shellHook = ''
            echo "Neko development environment"
            echo "  nix build .#image          - Build OCI image"
            echo "  nix build .#nekoServer     - Build server binary"
            echo "  nix build .#nekoClient     - Build client dist"
            echo "  nix run .#pushImage        - Push image to registry"
            echo ""
            echo "Version: ${versionInfo.version}"
            echo "Commit: ${versionInfo.gitCommit}"
            echo "SOURCE_DATE_EPOCH: ${toString versionInfo.SOURCE_DATE_EPOCH}"
        '';
      };

      # CI outputs (for GitHub Actions)
      apps.${system} = {
        # Build and check reproducibility
        check-reproducibility = {
          type = "app";
          program = toString (pkgs.writeShellScript "check-repro" ''
              set -euo pipefail
              echo "Building image..."
              nix build .#image

              echo "Rebuilding to verify reproducibility..."
              nix build .#image --check --rebuild

              echo "✅ Build is reproducible!"

              # Show NAR hash
              nix path-info --json .#image | ${pkgs.jq}/bin/jq '.[0] | {narHash, narSize}'
          '');
        };

        # Generate manifest (NAR hash + OCI digest)
        generate-manifest = {
          type = "app";
          program = toString (pkgs.writeShellScript "generate-manifest" ''
            ${pkgs.python3}/bin/python3 ${./scripts/publish-manifest.py}
          '');
        };
      };
    };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}
