{ pkgs
, lib
, nix2container
, nekoServer
, nekoClient
, xorgDeps
, runtimeEnv
, version
, SOURCE_DATE_EPOCH
}:

let
  # Create a user setup script
  setupUser = pkgs.writeShellScriptBin "setup-neko-user" ''
    #!/bin/bash
    set -e

    USERNAME=neko
    USER_UID=1000
    USER_GID=1000

    # Create group and user if they don't exist
    if ! getent group $USERNAME >/dev/null 2>&1; then
      groupadd --gid $USER_GID $USERNAME
    fi

    if ! getent passwd $USERNAME >/dev/null 2>&1; then
      useradd --uid $USER_UID --gid $USERNAME --shell /bin/bash --create-home $USERNAME
    fi

    # Add user to groups
    usermod -aG audio,video,pulse $USERNAME || true

    # Create necessary directories
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
    chown $USERNAME /tmp/.X11-unix/ || true

    mkdir -p /etc/neko /var/www /var/log/neko \
        /tmp/runtime-$USERNAME \
        /home/$USERNAME/.config/pulse \
        /home/$USERNAME/.local/share/xorg

    chmod 1777 /var/log/neko || true
    chown -R $USERNAME:$USERNAME /var/log/neko /tmp/runtime-$USERNAME /home/$USERNAME || true
  '';

  # Copy runtime configs to proper locations
  configFiles = pkgs.runCommand "neko-config-files" {} ''
    mkdir -p $out/etc/neko
    mkdir -p $out/etc/fonts/conf.d
    mkdir -p $out/usr/local/share/fonts
    mkdir -p $out/home/neko/.icons/default
    mkdir -p $out/home/neko/.config/pulse
    mkdir -p $out/usr/bin

    # Copy supervisord configs
    cp ${../runtime/supervisord.conf} $out/etc/neko/supervisord.conf
    cp ${../runtime/supervisord.dbus.conf} $out/etc/neko/supervisord.dbus.conf

    # Copy xorg config
    cp ${../runtime/xorg.conf} $out/etc/neko/xorg.conf

    # Copy pulseaudio config to user directory (to avoid collision with system pulse)
    cp ${../runtime/default.pa} $out/home/neko/.config/pulse/default.pa

    # Copy dbus wrapper
    cp ${../runtime/dbus} $out/usr/bin/dbus
    chmod +x $out/usr/bin/dbus

    # Copy Xresources
    cp ${../runtime/.Xresources} $out/home/neko/.Xresources

    # Copy icon theme
    cp -r ${../runtime/icon-theme}/* $out/home/neko/.icons/default/ || true

    # Copy fontconfig
    cp ${../runtime/fontconfig}/* $out/etc/fonts/conf.d/ || true

    # Copy fonts
    cp -r ${../runtime/fonts}/* $out/usr/local/share/fonts/ || true

    # Copy main neko config
    cp ${../config.yml} $out/etc/neko/neko.yaml
  '';

  # Combine all components
  rootfs = pkgs.buildEnv {
    name = "neko-rootfs";
    paths = [
      runtimeEnv
      configFiles
      setupUser

      # Add server binary and plugins
      (pkgs.runCommand "neko-server-install" {} ''
        mkdir -p $out/usr/bin
        mkdir -p $out/etc/neko/plugins

        cp ${nekoServer}/bin/neko $out/usr/bin/neko
        chmod +x $out/usr/bin/neko

        # Copy plugins if they exist
        if [ -d ${nekoServer}/plugins ]; then
          cp -r ${nekoServer}/plugins/* $out/etc/neko/plugins/ || true
        fi
      '')

      # Add client dist
      (pkgs.runCommand "neko-client-install" {} ''
        mkdir -p $out/var/www
        cp -r ${nekoClient}/* $out/var/www/
      '')

      # Add X.org drivers
      (pkgs.runCommand "neko-xorg-install" {} ''
        mkdir -p $out/usr/lib/xorg/modules/drivers
        mkdir -p $out/usr/lib/xorg/modules/input

        cp ${xorgDeps.dummyDriver} $out/usr/lib/xorg/modules/drivers/dummy_drv.so
        cp ${xorgDeps.nekoDriver} $out/usr/lib/xorg/modules/input/neko_drv.so
      '')
    ];

    pathsToLink = [ "/bin" "/usr" "/etc" "/var" "/home" "/tmp" ];
  };

in
nix2container.buildImage {
  name = "ghcr.io/m1k1o/neko/base";
  tag = version;

  # Maximum layers for optimization
  maxLayers = 100;

  # Copy the entire rootfs
  copyToRoot = [ rootfs ];

  # Deterministic timestamp (epoch or SOURCE_DATE_EPOCH)
  created = "1970-01-01T00:00:01Z";

  # Image configuration
  config = {
    # Command to run
    Cmd = [ "/usr/bin/supervisord" "-c" "/etc/neko/supervisord.conf" ];

    # Environment variables (from runtime/Dockerfile:95-101)
    Env = [
      "USER=neko"
      "DISPLAY=:99.0"
      "PULSE_SERVER=unix:/tmp/pulseaudio.socket"
      "XDG_RUNTIME_DIR=/tmp/runtime-neko"
      "NEKO_SERVER_BIND=:8080"
      "NEKO_PLUGINS_ENABLED=true"
      "NEKO_PLUGINS_DIR=/etc/neko/plugins/"
      "PATH=/usr/bin:/bin"
    ];

    # Exposed ports
    ExposedPorts = {
      "8080/tcp" = {};
    };

    # Working directory
    WorkingDir = "/home/neko";

    # Run as neko user (UID:GID)
    # Note: nix2container may need the user to exist in /etc/passwd
    # For now, we'll run as root and supervisord will su to neko
    # User = "neko";

    # Labels (from Dockerfile.tmpl:9)
    Labels = {
      "net.m1k1o.neko.api-version" = "3";
      "org.opencontainers.image.title" = "Neko";
      "org.opencontainers.image.description" = "Self-hosted virtual browser";
      "org.opencontainers.image.version" = version;
      "org.opencontainers.image.source" = "https://github.com/m1k1o/neko";
      "org.opencontainers.image.licenses" = "Apache-2.0";
      "dev.nix.build" = "true";
      "dev.nix.reproducible" = "true";
    };

    # Health check (from runtime/Dockerfile:105-108)
    Healthcheck = {
      Test = [
        "CMD-SHELL"
        "wget -O - http://localhost:8080/health || wget --no-check-certificate -O - https://localhost:8080/health || exit 1"
      ];
      Interval = 10000000000;  # 10s in nanoseconds
      Timeout = 5000000000;    # 5s
      Retries = 8;
    };
  };

  # Additional metadata
  meta = with lib; {
    description = "Neko base image - self-hosted virtual browser (Nix build)";
    homepage = "https://github.com/m1k1o/neko";
    license = licenses.asl20;
    platforms = platforms.linux;
    # Can be built from Darwin via cross-compilation
    broken = false;
  };
}
