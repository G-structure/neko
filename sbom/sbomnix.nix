{ pkgs
, nekoServer
, nekoClient
, xorgDeps
, image
}:

# SBOM generation using sbomnix (Nix-aware SBOM generator)
pkgs.writeShellApplication {
  name = "generate-neko-sbom";

  runtimeInputs = with pkgs; [
    sbomnix
    jq
  ];

  text = ''
    set -euo pipefail

    echo "Generating SBOM for Neko image..." >&2

    # Generate SBOM from the image derivation
    sbomnix ${image} \
      --type=spdx \
      --format=json \
      --output=/dev/stdout

    # Note: sbomnix will include all Nix dependencies,
    # providing a complete and accurate SBOM
  '';

  meta = with pkgs.lib; {
    description = "SBOM generator for Neko image using sbomnix";
    platforms = platforms.linux;
  };
}
