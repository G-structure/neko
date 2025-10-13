{ pkgs
, lib
, SOURCE_DATE_EPOCH ? 0
, buildPkgs ? pkgs  # Native build tools (for cross-compilation)
, ...
}:

let
  # Build xf86-video-dummy v0.3.8 with RandR support (patched)
  xf86-video-dummy-randr = pkgs.stdenv.mkDerivation {
    pname = "xf86-video-dummy-randr";
    version = "0.3.8";

    src = ../utils/xorg-deps/xf86-video-dummy/v0.3.8;

    nativeBuildInputs = with buildPkgs; [
      autoreconfHook
      pkg-config
      xorg.utilmacros
    ];

    depsBuildBuild = with buildPkgs; [
      pkg-config
    ];

    buildInputs = with pkgs; [
      xorg.xorgserver.dev
      xorg.xorgproto
    ];

    # Apply RandR patch
    patches = [ ../utils/xorg-deps/xf86-video-dummy/01_v0.3.8_xdummy-randr.patch ];

    inherit SOURCE_DATE_EPOCH;

    configureFlags = [ "--prefix=${placeholder "out"}" ];

    enableParallelBuilding = true;

    meta = with lib; {
      description = "Dummy video driver for X.org with RandR support";
      homepage = "https://www.x.org/";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };

  # Build custom neko input driver
  xf86-input-neko = pkgs.stdenv.mkDerivation {
    pname = "xf86-input-neko";
    version = "1.0.0";

    src = ../utils/xorg-deps/xf86-input-neko;

    nativeBuildInputs = with buildPkgs; [
      autoreconfHook
      pkg-config
      xorg.utilmacros
    ];

    depsBuildBuild = with buildPkgs; [
      pkg-config
    ];

    buildInputs = with pkgs; [
      xorg.xorgserver.dev
      xorg.xorgproto
    ];

    inherit SOURCE_DATE_EPOCH;

    preConfigure = ''
      ./autogen.sh --prefix=$out
    '';

    enableParallelBuilding = true;

    meta = with lib; {
      description = "Neko custom input driver for X.org";
      homepage = "https://github.com/m1k1o/neko";
      license = licenses.asl20;
      platforms = platforms.linux;
    };
  };

in
# Combine both drivers into a single output
pkgs.symlinkJoin {
  name = "neko-xorg-drivers";

  paths = [
    xf86-video-dummy-randr
    xf86-input-neko
  ];

  passthru = {
    inherit xf86-video-dummy-randr xf86-input-neko;

    # Provide paths for copying into the image
    dummyDriver = "${xf86-video-dummy-randr}/lib/xorg/modules/drivers/dummy_drv.so";
    nekoDriver = "${xf86-input-neko}/lib/xorg/modules/input/neko_drv.so";
  };

  meta = with lib; {
    description = "Neko X.org drivers bundle (dummy + neko input)";
    homepage = "https://github.com/m1k1o/neko";
    license = licenses.asl20;
    platforms = platforms.linux;
    # Support cross-compilation from Darwin
    broken = false;
  };
}
