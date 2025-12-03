{ pkgs
, lib
, version ? "2.5.0"
, SOURCE_DATE_EPOCH ? 0
, ...
}:

pkgs.buildNpmPackage rec {
  pname = "neko-client";
  inherit version;

  src = lib.cleanSourceWith {
    src = ../client;
    filter = path: type:
      let baseName = baseNameOf path;
      in !(lib.hasSuffix ".md" baseName) &&
         baseName != "Dockerfile" &&
         baseName != "node_modules";
  };

  # npm dependencies hash - computed from package-lock.json
  npmDepsHash = "sha256-L8/ToH05+mIAS9+cTMQ3tWMDkyJ/4LeiAU1ywbie9a4=";

  # Set SOURCE_DATE_EPOCH for reproducible timestamps
  inherit SOURCE_DATE_EPOCH;

  # Node.js 20 (18 removed in nixos-25.11)
  nodejs = pkgs.nodejs_20;

  # Use npm ci for more reproducible builds (respects package-lock.json exactly)
  npmBuildScript = "build";

  # Install phase - copy dist to output
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r dist/* $out/

    runHook postInstall
  '';

  # Don't run tests during build (they're run separately in CI)
  doCheck = false;

  meta = with lib; {
    description = "Neko client - Vue.js frontend for virtual browser streaming";
    homepage = "https://github.com/m1k1o/neko";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.all;  # Client build can run anywhere
  };
}
