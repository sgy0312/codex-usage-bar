#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
build_dir="$script_dir/build"
app_dir="$build_dir/Codex Usage Bar.app"
module_cache="$build_dir/module-cache"

if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
else
  sdk_path=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$app_dir/Contents/MacOS" "$module_cache"
cp "$script_dir/Info.plist" "$app_dir/Contents/Info.plist"

CLANG_MODULE_CACHE_PATH="$module_cache" swiftc \
  -swift-version 5 \
  -O \
  -sdk "$sdk_path" \
  -framework AppKit \
  "$script_dir/main.swift" \
  -o "$app_dir/Contents/MacOS/CodexUsageBar"

codesign --force --deep --sign - "$app_dir" >/dev/null
printf '%s\n' "$app_dir"
