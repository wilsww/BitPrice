#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

test_binary="$repo_root/build/BitPriceTests"
module_cache="$repo_root/.build-cache/module-cache"
sdk_path="$(xcrun --show-sdk-path)"
mkdir -p "$repo_root/build" "$module_cache"

sources=(
    Sources/BitPrice/DomainModels.swift
    Sources/BitPrice/PersistenceStore.swift
    Sources/BitPrice/ProcessLock.swift
    Sources/BitPrice/RESTClients.swift
    Sources/BitPrice/WebSocketDelegateAdapter.swift
    Sources/BitPrice/BinanceFeedController.swift
    Sources/BitPrice/AlertEngine.swift
    Sources/BitPrice/NotificationService.swift
    Sources/BitPrice/AppModel.swift
    Sources/BitPrice/PanelModel.swift
    Sources/BitPrice/PanelVisibility.swift
    Sources/BitPrice/Views.swift
    Tests/TestMain.swift
)

swiftc \
    -parse-as-library \
    -swift-version 6 \
    -warnings-as-errors \
    -O \
    -target arm64-apple-macosx14.0 \
    -sdk "$sdk_path" \
    -module-cache-path "$module_cache" \
    "${sources[@]}" \
    -o "$test_binary"

"$test_binary"
