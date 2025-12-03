{ pkgs
, lib
, version ? "2.5.0"
, gitCommit ? "unknown"
, gitBranch ? "master"
, gitTag ? ""
, SOURCE_DATE_EPOCH ? 0
, buildPkgs ? pkgs  # Native build tools (for cross-compilation)
, ...
}:

(pkgs.buildGoModule.override { go = pkgs.go_1_24; }) rec {
  pname = "neko-server";
  inherit version;

  src = lib.cleanSourceWith {
    src = ../server;
    filter = path: type:
      let baseName = baseNameOf path;
      in !(lib.hasSuffix ".md" baseName) &&
         baseName != "Dockerfile" &&
         baseName != "Dockerfile.bookworm" &&
         baseName != "vendor";  # Exclude vendor directory - Nix will fetch deps
  };

  # Use go mod download instead of vendoring
  proxyVendor = true;
  vendorHash = "sha256-NP5A+h8/ENdliyR+THo6FwnTWRH0JK0b9PmPFROeMik=";

  # Build dependencies (native tools for build platform)
  nativeBuildInputs = with buildPkgs; [
    pkg-config
  ];

  # For cross-compilation, we need build-time dependencies
  depsBuildBuild = with buildPkgs; [
    pkg-config
  ];

  buildInputs = with pkgs; [
    # X11 libraries
    xorg.libX11
    xorg.libXrandr
    xorg.libXtst

    # libxcvt (required for xorg.h)
    pkgs.libxcvt

    # GTK for dialogs
    gtk3

    # GStreamer for video encoding
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
  ];

  # Enable CGO for C bindings
  CGO_ENABLED = "1";

  # Set SOURCE_DATE_EPOCH for reproducibility
  inherit SOURCE_DATE_EPOCH;

  # Build flags - fix the timestamp issue from server/build:33
  ldflags =
    let
      # Use a more portable date command for cross-compilation
      buildDate = builtins.readFile (buildPkgs.runCommand "build-date" {
        nativeBuildInputs = [ buildPkgs.coreutils ];
      } ''
        date -u -d @${toString SOURCE_DATE_EPOCH} +'%Y-%m-%dT%H:%M:%SZ' > $out
      '');
    in [
      "-s"
      "-w"
      "-X 'm1k1o/neko.buildDate=${buildDate}'"
      "-X 'm1k1o/neko.gitCommit=${gitCommit}'"
      "-X 'm1k1o/neko.gitBranch=${gitBranch}'"
      "-X 'm1k1o/neko.gitTag=${gitTag}'"
    ];

  # Build only the main server binary
  subPackages = [ "cmd/neko" ];

  # Output binary path
  postInstall = ''
    mkdir -p $out/bin
    mv $out/bin/neko $out/bin/neko || true

    # Create plugins directory (plugins are built separately if needed)
    mkdir -p $out/plugins
  '';

  # Build plugins separately (Go plugins require exact same toolchain)
  # We'll create a separate derivation for plugins if the plugins/ directory exists
  passthru = {
    buildPlugins = buildPkgs.writeShellScriptBin "build-neko-plugins" ''
      set -e
      PLUGINS_DIR="${../server/plugins}"

      if [ ! -d "$PLUGINS_DIR" ]; then
        echo "No plugins directory found"
        exit 0
      fi

      mkdir -p plugins

      for plugPath in "$PLUGINS_DIR"/*; do
        if [ ! -d "$plugPath" ]; then
          continue
        fi

        if [ ! -f "$plugPath/go.plug.mod" ]; then
          echo "Skipping $plugPath (no go.plug.mod)"
          continue
        fi

        plugName=$(basename "$plugPath")
        echo "Building plugin: $plugName"

        (
          cd "$plugPath"
          ${buildPkgs.go}/bin/go build \
            -modfile=go.plug.mod \
            -buildmode=plugin \
            -buildvcs=false \
            -o "../../plugins/$plugName.so"
        )
      done
    '';
  };

  meta = with lib; {
    description = "Neko WebRTC server - self-hosted virtual browser";
    homepage = "https://github.com/m1k1o/neko";
    license = licenses.asl20;
    maintainers = [ ];
    # Can be built on Darwin and Linux, but runs on Linux
    platforms = platforms.linux;
    # Support cross-compilation from Darwin
    broken = false;
  };
}
