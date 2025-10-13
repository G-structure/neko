{ lib, src }:

let
  # Try to read git info from the source if it's a git checkout
  gitRevision = src.rev or "unknown";
  gitShortRev = if gitRevision != "unknown"
    then builtins.substring 0 7 gitRevision
    else "unknown";

  # Try to get git branch
  gitBranch = src.ref or "master";

  # Try to get git tag (check if we're on a version tag)
  # This is a simplified version - in practice, you'd determine this from CI env vars
  gitTag = src.tag or "";

  # Extract version from package.json or git tag
  clientPackageJson = builtins.fromJSON (builtins.readFile "${src}/client/package.json");
  version =
    if gitTag != "" && lib.hasPrefix "v" gitTag
    then lib.removePrefix "v" gitTag
    else clientPackageJson.version;

  # Compute SOURCE_DATE_EPOCH from git commit timestamp
  # In a flake context, we use the lastModified from the flake itself
  SOURCE_DATE_EPOCH = src.lastModified or 0;

in {
  inherit version gitRevision gitBranch gitTag SOURCE_DATE_EPOCH;

  # Short commit for display
  gitCommit = gitShortRev;

  # Full commit for SLSA provenance
  gitCommitFull = gitRevision;

  # Formatted build date for the server binary (ISO 8601)
  buildDate =
    if SOURCE_DATE_EPOCH != 0
    then builtins.readFile (
      builtins.toFile "build-date" (
        builtins.toString (
          # Convert epoch to ISO 8601 - we'll use a simple approach
          # In practice, this would be computed at build time
          "1970-01-01T00:00:00Z"  # Placeholder - will be replaced at build time
        )
      )
    )
    else "unknown";
}
