{ pkgs
, lib
, nekoServer
, nekoClient
, xorgDeps
, runtimeEnv
, version
, SOURCE_DATE_EPOCH
}:

let
  # Create an entrypoint script that sets up the environment before starting supervisord
  entrypoint = pkgs.writeShellScriptBin "entrypoint" ''
    #!/bin/bash
    set -e

    USERNAME=neko
    USER_UID=1000
    USER_GID=1000

    # Create system groups first (audio, video, pulse) - only if they don't exist
    getent group audio >/dev/null 2>&1 || groupadd -r audio
    getent group video >/dev/null 2>&1 || groupadd -r video
    getent group pulse >/dev/null 2>&1 || groupadd -r pulse

    # Create neko group and user if they don't exist
    getent group $USERNAME >/dev/null 2>&1 || groupadd --gid $USER_GID $USERNAME

    if ! getent passwd $USERNAME >/dev/null 2>&1; then
      useradd --uid $USER_UID --gid $USERNAME --shell /bin/bash --create-home $USERNAME
    fi

    # Add user to system groups
    usermod -aG audio,video,pulse $USERNAME 2>/dev/null || true

    # Create necessary runtime directories
    mkdir -p /var/run /var/log /var/lock /run

    # Create /tmp with proper permissions - must be world-writable with sticky bit for X server lock files
    mkdir -p /tmp
    chmod 1777 /tmp

    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
    # X server expects /tmp/.X11-unix to be owned by root
    chown root:root /tmp/.X11-unix/ 2>/dev/null || true

    mkdir -p /etc/neko /var/www /var/log/neko \
        /tmp/runtime-$USERNAME \
        /tmp/fontconfig-cache \
        /home/$USERNAME/.config/pulse \
        /home/$USERNAME/.config/chromium \
        /home/$USERNAME/.local/share/xorg

    chmod 1777 /var/log/neko || true
    chmod 1777 /tmp/fontconfig-cache || true
    chmod 700 /tmp/runtime-$USERNAME || true

    # Ensure home directory is fully owned by neko user
    chown -R $USER_UID:$USER_GID /home/$USERNAME 2>/dev/null || true

    # Fix permissions for neko logs and runtime
    chown -R $USER_UID:$USER_GID /var/log/neko /tmp/runtime-$USERNAME 2>/dev/null || true

    # Start supervisord
    exec /bin/supervisord -c /etc/neko/supervisord.conf
  '';

  # Copy runtime configs to proper locations
  configFiles = pkgs.runCommand "neko-config-files" {} ''
    mkdir -p $out/etc/neko
    mkdir -p $out/etc/fonts/conf.d
    mkdir -p $out/usr/local/share/fonts
    mkdir -p $out/home/neko/.icons/default
    mkdir -p $out/home/neko/.config/pulse
    mkdir -p $out/usr/bin

    # Copy supervisord configs and remove unsupported directives for nix supervisord
    sed -e '/^chown=/d' -e '/^user=root/d' ${../runtime/supervisord.conf} > $out/etc/neko/supervisord.conf

    # Note: DBus is disabled for now - it requires complex user/group setup in Nix containers
    # PulseAudio will log warnings but still function without it
    mkdir -p $out/etc/neko/supervisord

    # Copy xorg config and add ModulePath for Nix modules and custom drivers
    # X server needs to find both the Nix xorg modules and our custom dummy/neko drivers
    cat > $out/etc/neko/xorg.conf << XORG_HEADER
Section "Files"
  ModulePath "/usr/lib/xorg/modules"
  ModulePath "${runtimeEnv}/lib/xorg/modules"
EndSection

XORG_HEADER
    cat ${../runtime/xorg.conf} >> $out/etc/neko/xorg.conf

    # Copy pulseaudio config to user directory (to avoid collision with system pulse)
    cp ${../runtime/default.pa} $out/home/neko/.config/pulse/default.pa

    # Note: DBus wrapper removed - DBus is disabled in this Nix build

    # Copy Xresources
    cp ${../runtime/.Xresources} $out/home/neko/.Xresources

    # Copy icon theme
    cp -r ${../runtime/icon-theme}/* $out/home/neko/.icons/default/ || true

    # Copy fontconfig and create fonts.conf that references Nix store
    cp ${../runtime/fontconfig}/* $out/etc/fonts/conf.d/ || true

    # Create a basic fonts.conf that fontconfig can find
    cat > $out/etc/fonts/fonts.conf << FONTCONF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>/usr/local/share/fonts</dir>
  <dir>/usr/share/fonts</dir>
  <dir>${runtimeEnv}/share/fonts</dir>
  <dir>~/.fonts</dir>
  <cachedir>/tmp/fontconfig-cache</cachedir>
  <include ignore_missing="yes">/etc/fonts/conf.d</include>
  <include ignore_missing="yes">${runtimeEnv}/etc/fonts/conf.d</include>
</fontconfig>
FONTCONF

    # Copy fonts
    cp -r ${../runtime/fonts}/* $out/usr/local/share/fonts/ || true

    # Copy main neko config
    cp ${../config.yml} $out/etc/neko/neko.yaml
  '';

  # Copy Chromium app configuration files
  chromiumConfigFiles = pkgs.runCommand "neko-chromium-config" {} ''
    mkdir -p $out/etc/neko/supervisord
    mkdir -p $out/home/neko/.config/chromium/Default
    mkdir -p $out/etc/chromium/policies/managed
    mkdir -p $out/etc/neko

    # Copy supervisord config for chromium, adding --no-sandbox for container use
    # Chromium's SUID sandbox doesn't work in containers without special setup
    sed 's|command=/usr/bin/chromium|command=/usr/bin/chromium --no-sandbox|' \
      ${../apps/chromium/supervisord.conf} > $out/etc/neko/supervisord/chromium.conf

    # Copy chromium preferences
    cp ${../apps/chromium/preferences.json} $out/home/neko/.config/chromium/Default/Preferences

    # Copy chromium policies
    cp ${../apps/chromium/policies.json} $out/etc/chromium/policies/managed/policies.json

    # Copy openbox config
    cp ${../apps/chromium/openbox.xml} $out/etc/neko/openbox.xml
  '';

  # Add server binary and plugins
  serverInstall = pkgs.runCommand "neko-server-install" {} ''
    mkdir -p $out/usr/bin
    mkdir -p $out/etc/neko/plugins

    cp ${nekoServer}/bin/neko $out/usr/bin/neko
    chmod +x $out/usr/bin/neko

    # Copy plugins if they exist
    if [ -d ${nekoServer}/plugins ]; then
      cp -r ${nekoServer}/plugins/* $out/etc/neko/plugins/ || true
    fi
  '';

  # Add client dist
  clientInstall = pkgs.runCommand "neko-client-install" {} ''
    mkdir -p $out/var/www
    cp -r ${nekoClient}/* $out/var/www/
  '';

  # Add X.org drivers
  xorgInstall = pkgs.runCommand "neko-xorg-install" {} ''
    mkdir -p $out/usr/lib/xorg/modules/drivers
    mkdir -p $out/usr/lib/xorg/modules/input

    cp ${xorgDeps.dummyDriver} $out/usr/lib/xorg/modules/drivers/dummy_drv.so
    cp ${xorgDeps.nekoDriver} $out/usr/lib/xorg/modules/input/neko_drv.so
  '';

  # Chromium runtime environment
  chromiumEnv = pkgs.buildEnv {
    name = "neko-chromium-env";
    paths = with pkgs; [
      # Chromium browser
      chromium

      # Window manager
      openbox
    ];

    pathsToLink = [ "/bin" "/lib" "/share" ];
  };

  # Create /usr/bin symlinks for binaries that supervisor configs expect
  # Supervisor configs hardcode /usr/bin/* paths, but Nix puts binaries in /bin/
  usrBinSymlinks = pkgs.runCommand "neko-usr-bin-symlinks" {} ''
    mkdir -p $out/usr/bin

    # From chromiumEnv
    ln -s ${chromiumEnv}/bin/chromium $out/usr/bin/chromium
    ln -s ${chromiumEnv}/bin/openbox $out/usr/bin/openbox

    # From runtimeEnv - X server (try Xorg first, fall back to X)
    if [ -e ${runtimeEnv}/bin/Xorg ]; then
      ln -s ${runtimeEnv}/bin/Xorg $out/usr/bin/X
    elif [ -e ${runtimeEnv}/bin/X ]; then
      ln -s ${runtimeEnv}/bin/X $out/usr/bin/X
    fi

    # From runtimeEnv - audio and dbus
    ln -s ${runtimeEnv}/bin/pulseaudio $out/usr/bin/pulseaudio
    ln -s ${runtimeEnv}/bin/dbus-daemon $out/usr/bin/dbus-daemon

    # Additional utilities that Go code calls via exec.Command
    ln -s ${runtimeEnv}/bin/xclip $out/usr/bin/xclip
    ln -s ${runtimeEnv}/bin/xdotool $out/usr/bin/xdotool
    ln -s ${runtimeEnv}/bin/setxkbmap $out/usr/bin/setxkbmap
  '';

in
pkgs.dockerTools.buildLayeredImage {
  # Image name and tag
  name = "neko-chromium";
  tag = version;

  # Maximum number of layers for optimal caching (reduced to avoid max depth errors)
  maxLayers = 100;

  # Layer contents - Nix will automatically optimize layer distribution
  # based on dependency popularity for better cache hits
  contents = [
    # Runtime environment (base system, X11, audio, video, fonts)
    runtimeEnv

    # Configuration files (most frequently changed)
    configFiles

    # Chromium-specific configs
    chromiumConfigFiles

    # Entrypoint script
    entrypoint

    # Application components
    serverInstall
    clientInstall

    # Custom X.org drivers
    xorgInstall

    # Chromium browser and window manager
    chromiumEnv

    # Symlinks from /usr/bin/* to actual binary locations
    usrBinSymlinks
  ];

  # Image configuration
  config = {
    # Command to run (entrypoint sets up environment and starts supervisord)
    Cmd = [ "/bin/entrypoint" ];

    # Environment variables (from runtime/Dockerfile:95-101)
    Env = [
      "USER=neko"
      "HOME=/home/neko"
      "DISPLAY=:99.0"
      "PULSE_SERVER=unix:/tmp/pulseaudio.socket"
      "XDG_RUNTIME_DIR=/tmp/runtime-neko"
      "NEKO_SERVER_BIND=:8080"
      "NEKO_PLUGINS_ENABLED=true"
      "NEKO_PLUGINS_DIR=/etc/neko/plugins/"
      # PATH includes Nix store paths for binaries
      "PATH=/usr/bin:/bin:${runtimeEnv}/bin:${chromiumEnv}/bin"
      # GStreamer plugin path for video encoding
      "GST_PLUGIN_PATH=${runtimeEnv}/lib/gstreamer-1.0"
      # XDG paths for freedesktop integration (icons, mime types, etc.)
      "XDG_DATA_DIRS=${runtimeEnv}/share:${chromiumEnv}/share:/usr/share"
      # Fontconfig path for font rendering
      "FONTCONFIG_PATH=${runtimeEnv}/etc/fonts"
    ];

    # Exposed ports
    ExposedPorts = {
      "8080/tcp" = {};
    };

    # Working directory
    WorkingDir = "/home/neko";

    # Labels (from Dockerfile.tmpl:9)
    Labels = {
      "net.m1k1o.neko.api-version" = "3";
      "org.opencontainers.image.title" = "Neko Chromium";
      "org.opencontainers.image.description" = "Self-hosted virtual browser with Chromium";
      "org.opencontainers.image.version" = version;
      "org.opencontainers.image.source" = "https://github.com/m1k1o/neko";
      "org.opencontainers.image.licenses" = "Apache-2.0";
      "dev.nix.build" = "true";
      "dev.nix.reproducible" = "true";
    };
  };
}
