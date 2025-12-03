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

    # Initialize /etc/passwd and /etc/group if they're symlinks to read-only nix store
    # This is needed because fakeNss creates read-only symlinks but we need writable files
    if [ -L /etc/passwd ] || [ ! -w /etc/passwd ]; then
      # Copy content from symlink target or create fresh
      if [ -L /etc/passwd ]; then
        cp --remove-destination "$(readlink /etc/passwd)" /etc/passwd 2>/dev/null || true
      fi
      # Ensure we have at least root and nobody
      if [ ! -f /etc/passwd ] || [ ! -s /etc/passwd ]; then
        echo "root:x:0:0:root:/root:/bin/bash" > /etc/passwd
        echo "nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin" >> /etc/passwd
      fi
      chmod 644 /etc/passwd
    fi

    if [ -L /etc/group ] || [ ! -w /etc/group ]; then
      if [ -L /etc/group ]; then
        cp --remove-destination "$(readlink /etc/group)" /etc/group 2>/dev/null || true
      fi
      if [ ! -f /etc/group ] || [ ! -s /etc/group ]; then
        echo "root:x:0:" > /etc/group
        echo "nobody:x:65534:" >> /etc/group
      fi
      chmod 644 /etc/group
    fi

    # Initialize /etc/shadow if needed
    if [ ! -f /etc/shadow ]; then
      echo "root:*:19000:0:99999:7:::" > /etc/shadow
      echo "nobody:*:19000:0:99999:7:::" >> /etc/shadow
      chmod 640 /etc/shadow
    fi

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

    # Create dbus runtime directories (required for system bus)
    # Note: dbus uses /run/dbus, which may be different from /var/run/dbus
    mkdir -p /run/dbus /var/run/dbus
    rm -f /run/dbus/pid /var/run/dbus/pid 2>/dev/null || true
    # Create symlink if they're different paths
    ln -sf /run/dbus/system_bus_socket /var/run/dbus/system_bus_socket 2>/dev/null || true

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

    # DBus support - create custom config and wrapper script for container use
    mkdir -p $out/etc/neko/supervisord
    mkdir -p $out/usr/share/dbus-1
    mkdir -p $out/etc/dbus-1

    # Create a minimal container-friendly dbus system config
    # This config runs as root (no messagebus user needed) and uses /run/dbus
    cat > $out/usr/share/dbus-1/system-container.conf << 'DBUS_CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <!-- System bus type for inter-process communication -->
  <type>system</type>

  <!-- Run as root in container (no messagebus user needed) -->
  <!-- Note: This is safe in a container where root is isolated -->

  <!-- Don't fork, supervisord manages the process -->
  <!-- <fork/> -->

  <!-- Write pid file -->
  <pidfile>/run/dbus/pid</pidfile>

  <!-- Only allow socket-credentials-based authentication -->
  <auth>EXTERNAL</auth>

  <!-- Listen on Unix socket -->
  <listen>unix:path=/run/dbus/system_bus_socket</listen>

  <!-- Default policy: allow all connections and message sending -->
  <!-- This is permissive for container use where isolation is provided by Docker -->
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_type="method_call"/>
    <allow send_type="signal"/>
    <allow send_type="method_return"/>
    <allow send_type="error"/>
    <allow receive_type="method_call"/>
    <allow receive_type="signal"/>
    <allow receive_type="method_return"/>
    <allow receive_type="error"/>
  </policy>
</busconfig>
DBUS_CONF

    # Create the dbus wrapper script that supervisord will run
    cat > $out/usr/bin/dbus << 'DBUS_SCRIPT'
#!/bin/sh

# Ensure dbus runtime directory exists
mkdir -p /run/dbus

# Clean up stale pid file
rm -f /run/dbus/pid 2>/dev/null

# Run dbus-daemon with container-friendly config
exec /usr/bin/dbus-daemon --nofork --print-pid --config-file=/usr/share/dbus-1/system-container.conf
DBUS_SCRIPT
    chmod +x $out/usr/bin/dbus

    # Copy the dbus supervisord config (runs dbus with priority 100)
    # Remove user=root directive as Nix supervisord doesn't support it
    sed -e '/^user=root/d' ${../runtime/supervisord.dbus.conf} > $out/etc/neko/supervisord/dbus.conf

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

    # Symlink dbus session config from Nix store (system.conf is replaced by our container config above)
    ln -sf ${runtimeEnv}/share/dbus-1/session.conf $out/usr/share/dbus-1/session.conf

    # Copy Xresources
    cp ${../runtime/.Xresources} $out/home/neko/.Xresources

    # Copy icon theme
    cp -r ${../runtime/icon-theme}/* $out/home/neko/.icons/default/ || true

    # Copy fontconfig and create fonts.conf that references Nix store
    cp ${../runtime/fontconfig}/* $out/etc/fonts/conf.d/ || true

    # Symlink essential font rendering configs from fontconfig package
    # These enable proper antialiasing, hinting, and subpixel rendering
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/10-hinting-slight.conf $out/etc/fonts/conf.d/
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf $out/etc/fonts/conf.d/
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/10-yes-antialias.conf $out/etc/fonts/conf.d/
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/11-lcdfilter-default.conf $out/etc/fonts/conf.d/
    # Generic font family mappings
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/45-generic.conf $out/etc/fonts/conf.d/
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/45-latin.conf $out/etc/fonts/conf.d/
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/49-sansserif.conf $out/etc/fonts/conf.d/
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/60-generic.conf $out/etc/fonts/conf.d/
    ln -sf ${runtimeEnv}/share/fontconfig/conf.avail/60-latin.conf $out/etc/fonts/conf.d/

    # Create fonts.conf with proper font rendering settings
    cat > $out/etc/fonts/fonts.conf << FONTCONF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- Font directories -->
  <dir>/usr/local/share/fonts</dir>
  <dir>/usr/share/fonts</dir>
  <dir>${runtimeEnv}/share/fonts</dir>
  <dir>~/.fonts</dir>
  <cachedir>/tmp/fontconfig-cache</cachedir>

  <!-- Include config fragments -->
  <include ignore_missing="yes">/etc/fonts/conf.d</include>
  <include ignore_missing="yes">${runtimeEnv}/etc/fonts/conf.d</include>

  <!-- Font rendering settings for crisp, clear fonts -->
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
    <edit name="autohint" mode="assign"><bool>false</bool></edit>
  </match>

  <!-- Disable embedded bitmaps in fonts like Calibri -->
  <match target="font">
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>

  <!-- Default sans-serif font -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>DejaVu Sans</family>
      <family>Liberation Sans</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>

  <!-- Default serif font -->
  <alias>
    <family>serif</family>
    <prefer>
      <family>DejaVu Serif</family>
      <family>Liberation Serif</family>
      <family>Noto Serif</family>
    </prefer>
  </alias>

  <!-- Default monospace font -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>DejaVu Sans Mono</family>
      <family>Liberation Mono</family>
      <family>Noto Sans Mono</family>
    </prefer>
  </alias>
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
    # Fake NSS for /etc/passwd and /etc/group (required by dbus and other services)
    pkgs.dockerTools.fakeNss

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
      # DBus system bus address for inter-process communication
      "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket"
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
