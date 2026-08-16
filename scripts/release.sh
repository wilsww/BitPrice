#!/bin/bash
#
# Packages a release archive from a clean build.
#
# This script builds and packages only. It does not tag, push, or publish:
# those are outward-facing actions and belong to a deliberate decision, not
# to a build script that might be run to see what happens.
#
# Usage:
#   bash scripts/release.sh 1.0
#
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [ $# -ne 1 ]; then
    echo "Usage: bash scripts/release.sh <version>" >&2
    echo "Example: bash scripts/release.sh 1.0" >&2
    exit 1
fi

version="$1"

# A version that disagrees with the bundle produces an archive whose name
# promises one thing and whose About box says another, and the mismatch is
# invisible until a user reports it.
plist_version="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
if [ "$version" != "$plist_version" ]; then
    echo "Version mismatch: argument is $version, Info.plist says $plist_version" >&2
    echo "Update CFBundleShortVersionString in Info.plist, or pass $plist_version" >&2
    exit 1
fi

# Releasing from a dirty tree ships code that exists on no commit, so the
# archive cannot be rebuilt from the repository later.
if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is not clean. Commit or stash before releasing." >&2
    git status --short >&2
    exit 1
fi

echo "==> Running tests"
bash scripts/run-tests.sh

echo "==> Building"
bash scripts/build-app.sh

app_path="$repo_root/build/BitPrice.app"
archive_path="$repo_root/build/BitPrice-$version.zip"

if [ ! -d "$app_path" ]; then
    echo "Build did not produce $app_path" >&2
    exit 1
fi

# ditto, not zip. The `zip` command flattens symlinks and drops extended
# attributes, which breaks the bundle's code signature: the archive expands
# into an application macOS refuses to launch, and the failure appears only
# after download.
echo "==> Packaging"
rm -f "$archive_path"
ditto -c -k --keepParent "$app_path" "$archive_path"

# Verify the archive rather than the build directory. What ships is what was
# packaged, and only expanding it proves the signature survived.
echo "==> Verifying the packaged archive"
verify_dir="$(mktemp -d)"
trap 'rm -rf "$verify_dir"' EXIT
ditto -x -k "$archive_path" "$verify_dir"
codesign --verify --deep --strict --verbose=2 "$verify_dir/BitPrice.app"

size="$(du -h "$archive_path" | cut -f1)"
echo
echo "Packaged $archive_path ($size)"
echo
echo "This archive is ad-hoc signed and not notarized. macOS quarantines"
echo "downloaded copies, so users must clear the attribute after moving the"
echo "app into place. The README documents the command."
echo
echo "To publish, review scripts/release.sh's header and run the tag and"
echo "release commands yourself."
