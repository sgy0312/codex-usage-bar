#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
build_dir="$script_dir/build"
app_dir="$build_dir/Codex Usage Bar.app"
module_cache="$build_dir/module-cache"
source_dir="$script_dir/Sources/CodexUsageBar"
info_plist="$script_dir/Resources/Info.plist"

sdk_path=$(xcrun --sdk macosx --show-sdk-path)

if [[ ! -d "$source_dir" ]]; then
  print -u2 "未找到源码目录：$source_dir"
  exit 1
fi

if [[ ! -f "$info_plist" ]]; then
  print -u2 "未找到 Info.plist：$info_plist"
  exit 1
fi

mkdir -p "$app_dir/Contents/MacOS" "$module_cache"
cp "$info_plist" "$app_dir/Contents/Info.plist"

CLANG_MODULE_CACHE_PATH="$module_cache" swiftc \
  -swift-version 5 \
  -O \
  -sdk "$sdk_path" \
  -framework AppKit \
  "$source_dir"/*.swift \
  -o "$app_dir/Contents/MacOS/CodexUsageBar"

codesign --force --deep --sign - "$app_dir" >/dev/null
printf '%s\n' "$app_dir"
