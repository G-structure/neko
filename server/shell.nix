{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Go toolchain
    go_1_24

    # Build tools
    pkg-config

    # GStreamer
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
  ];

  shellHook = ''
    echo "Neko macOS development environment"
    echo "Go version: $(go version)"
    echo ""
    echo "Build command:"
    echo "  CGO_ENABLED=1 go build -o bin/neko ./cmd/neko"
    echo ""
  '';
}
