#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

app_path="$repo_root/build/BitPrice.app"
executable_path="$app_path/Contents/MacOS/BitPrice"
module_cache="$repo_root/.build-cache/module-cache"
sdk_path="$(xcrun --show-sdk-path)"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$module_cache"

bash "$repo_root/scripts/make-icon.sh" "$app_path/Contents/Resources/AppIcon.icns"

sources=()
while IFS= read -r -d '' source_file; do
    sources+=("$source_file")
done < <(find "$repo_root/Sources/BitPrice" -type f -name '*.swift' -print0)

if [ "${#sources[@]}" -eq 0 ]; then
    echo "No Swift source files found" >&2
    exit 1
fi

swiftc \
    -parse-as-library \
    -swift-version 6 \
    -warnings-as-errors \
    -O \
    -target arm64-apple-macosx14.0 \
    -sdk "$sdk_path" \
    -module-cache-path "$module_cache" \
    "${sources[@]}" \
    -o "$executable_path"

cp "$repo_root/Info.plist" "$app_path/Contents/Info.plist"
plutil -lint "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
codesign --verify --verbose=2 "$app_path"
otool -L "$executable_path"

echo "Built and verified $app_path"
echo "Launch with: open build/BitPrice.app"
