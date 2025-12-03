{ pkgs
, lib
, ...
}:

# This replaces the runtime/Dockerfile apt packages with Nix equivalents
pkgs.buildEnv {
  name = "neko-runtime-env";

  paths = with pkgs; [
    # Core utilities (from runtime/Dockerfile:16)
    wget
    cacert
    python3Packages.supervisor  # Python 3 supervisor (no python2 needed)

    # Audio system
    pulseaudio
    dbus

    # X11 server and video
    xorg.xorgserver
    xorg.xf86videodummy  # Base dummy driver (we override with our patched version)
    libxcvt  # Replaces manual .deb download

    # X11 libraries (from runtime/Dockerfile:18)
    cairo
    xorg.libxcb
    xorg.libXrandr
    xorg.libXv
    libopus
    libvpx

    # File management and clipboard (from runtime/Dockerfile:24)
    zip
    curl
    xdotool
    xclip
    xorg.setxkbmap  # Required by neko server for keyboard layout
    gtk3

    # GStreamer for video encoding (from runtime/Dockerfile:27-29)
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    # gst-plugins-good includes pulseaudio plugin
    # Note: gst-omx might need special handling for hardware encoding

    # Fonts (from runtime/Dockerfile:59-72)
    # Emoji fonts
    noto-fonts-color-emoji

    # Chinese fonts
    wqy_zenhei
    wqy_microhei

    # Japanese fonts
    ipafont

    # Korean fonts
    unfonts-core

    # Additional international fonts
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-cjk-sans

    # System utilities
    coreutils
    bash
    shadow  # for user management
    util-linux
    fontconfig  # Font configuration and rendering
  ];

  pathsToLink = [
    "/bin"
    "/lib"
    "/share"
    "/etc"
    "/include"  # For potential plugins
  ];

  # Create necessary directories and setup
  extraOutputsToInstall = [ "dev" "man" ];

  meta = with lib; {
    description = "Neko runtime environment with all system dependencies";
    platforms = platforms.linux;
    # Support cross-compilation from Darwin
    broken = false;
  };
}
