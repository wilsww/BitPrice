#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${1:-$repo_root/build/AppIcon.icns}"
sdk_path="$(xcrun --show-sdk-path)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/bitprice-icon.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

iconset_path="$work_dir/AppIcon.iconset"
generator_path="$work_dir/make-icon"
module_cache="$work_dir/module-cache"
mkdir -p "$iconset_path" "$module_cache" "$(dirname "$output_path")"

swiftc \
    -swift-version 6 \
    -warnings-as-errors \
    -O \
    -target arm64-apple-macosx14.0 \
    -sdk "$sdk_path" \
    -module-cache-path "$module_cache" \
    "$repo_root/scripts/make-icon.swift" \
    -o "$generator_path"

"$generator_path" "$iconset_path"
if ! iconutil -c icns "$iconset_path" -o "$output_path" 2>"$work_dir/iconutil-pack.log"; then
    # macOS 15.6's iconutil packer can reject even a complete iconset that it
    # just extracted from an Apple system icon. Preserve the required attempt,
    # then write the same standard PNG representations into an ICNS container.
    "$generator_path" --pack "$iconset_path" "$output_path"
fi
test -s "$output_path"

# iconutil's decoder remains an independent validation that the output is a
# real ICNS file and contains the standard representations.
iconutil -c iconset "$output_path" -o "$work_dir/Verified.iconset"
test "$(find "$work_dir/Verified.iconset" -type f -name '*.png' | wc -l | tr -d ' ')" -eq 10
