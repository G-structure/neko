#!/usr/bin/env python3
"""
Neko Release Manifest Generator

Generates a JSON manifest that maps Nix NAR hashes to OCI image digests,
enabling end-to-end verification of reproducible builds.

Usage:
    ./scripts/publish-manifest.py [--image-ref IMAGE_REF] [--output FILE]

Example:
    ./scripts/publish-manifest.py --image-ref ghcr.io/m1k1o/neko/base:latest
"""

import json
import subprocess
import sys
import argparse
import os
from datetime import datetime
from typing import Dict, Any


def run_command(cmd: list[str], capture=True) -> str:
    """Run a shell command and return output."""
    try:
        if capture:
            result = subprocess.run(
                cmd,
                check=True,
                capture_output=True,
                text=True
            )
            return result.stdout.strip()
        else:
            subprocess.run(cmd, check=True)
            return ""
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {' '.join(cmd)}", file=sys.stderr)
        print(f"Error: {e.stderr if capture else e}", file=sys.stderr)
        sys.exit(1)


def get_nix_path_info() -> Dict[str, Any]:
    """Get NAR hash and metadata from Nix store."""
    print("Getting Nix path info...", file=sys.stderr)

    # Build the image if not already built
    result_path = run_command(["nix", "build", ".#image", "--no-link", "--print-out-paths"])

    # Get path info
    path_info_json = run_command(["nix", "path-info", "--json", result_path])
    path_info = json.loads(path_info_json)[0]

    return {
        "storePath": path_info["path"],
        "narHash": path_info["narHash"],
        "narSize": path_info["narSize"],
        "references": path_info.get("references", []),
    }


def get_oci_digest(image_ref: str) -> Dict[str, Any]:
    """Get OCI manifest digest from registry using skopeo."""
    print(f"Getting OCI digest for {image_ref}...", file=sys.stderr)

    try:
        inspect_output = run_command(["skopeo", "inspect", f"docker://{image_ref}"])
        inspect_data = json.loads(inspect_output)

        return {
            "digest": inspect_data.get("Digest", ""),
            "mediaType": inspect_data.get("MediaType", ""),
            "created": inspect_data.get("Created", ""),
            "architecture": inspect_data.get("Architecture", ""),
            "os": inspect_data.get("Os", ""),
        }
    except Exception as e:
        print(f"Warning: Could not fetch OCI digest: {e}", file=sys.stderr)
        print("Manifest will not include OCI digest.", file=sys.stderr)
        return {}


def get_git_info() -> Dict[str, Any]:
    """Get current git commit information."""
    print("Getting git info...", file=sys.stderr)

    try:
        commit = run_command(["git", "rev-parse", "HEAD"])
        short_commit = run_command(["git", "rev-parse", "--short", "HEAD"])
        branch = run_command(["git", "rev-parse", "--abbrev-ref", "HEAD"])

        # Try to get tag if we're on one
        try:
            tag = run_command(["git", "describe", "--exact-match", "--tags", "HEAD"])
        except:
            tag = ""

        return {
            "commit": commit,
            "shortCommit": short_commit,
            "branch": branch,
            "tag": tag,
        }
    except Exception as e:
        print(f"Warning: Could not get git info: {e}", file=sys.stderr)
        return {}


def get_version() -> str:
    """Extract version from client package.json."""
    try:
        with open("client/package.json", "r") as f:
            package_data = json.load(f)
            return package_data.get("version", "unknown")
    except Exception as e:
        print(f"Warning: Could not read version: {e}", file=sys.stderr)
        return "unknown"


def generate_manifest(image_ref: str = None) -> Dict[str, Any]:
    """Generate the complete release manifest."""
    manifest = {
        "version": get_version(),
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "git": get_git_info(),
        "nix": get_nix_path_info(),
    }

    # Add OCI info if image ref provided
    if image_ref:
        manifest["oci"] = get_oci_digest(image_ref)
        manifest["oci"]["imageRef"] = image_ref

    # Add verification instructions
    manifest["verification"] = {
        "nix": {
            "command": f"nix build .#image && nix path-info --json ./result | jq '.[0].narHash'",
            "expectedHash": manifest["nix"]["narHash"],
        }
    }

    if image_ref and manifest.get("oci", {}).get("digest"):
        manifest["verification"]["oci"] = {
            "command": f"skopeo inspect docker://{image_ref} | jq -r .Digest",
            "expectedDigest": manifest["oci"]["digest"],
        }

    return manifest


def main():
    parser = argparse.ArgumentParser(
        description="Generate Neko release manifest with NAR and OCI hashes"
    )
    parser.add_argument(
        "--image-ref",
        help="OCI image reference (e.g., ghcr.io/m1k1o/neko/base:latest)",
        default=None,
    )
    parser.add_argument(
        "--output",
        "-o",
        help="Output file (default: stdout)",
        default=None,
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON output",
    )

    args = parser.parse_args()

    # Generate manifest
    manifest = generate_manifest(image_ref=args.image_ref)

    # Format output
    if args.pretty:
        output = json.dumps(manifest, indent=2, sort_keys=False)
    else:
        output = json.dumps(manifest, separators=(',', ':'))

    # Write output
    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Manifest written to {args.output}", file=sys.stderr)
    else:
        print(output)

    # Print summary to stderr
    print("\n" + "=" * 60, file=sys.stderr)
    print("Release Manifest Summary", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    print(f"Version:     {manifest['version']}", file=sys.stderr)
    print(f"NAR Hash:    {manifest['nix']['narHash']}", file=sys.stderr)
    print(f"NAR Size:    {manifest['nix']['narSize']:,} bytes", file=sys.stderr)

    if "oci" in manifest and manifest["oci"].get("digest"):
        print(f"OCI Digest:  {manifest['oci']['digest']}", file=sys.stderr)

    if manifest.get("git", {}).get("commit"):
        print(f"Git Commit:  {manifest['git']['commit']}", file=sys.stderr)

    print("=" * 60, file=sys.stderr)


if __name__ == "__main__":
    main()
