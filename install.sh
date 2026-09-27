#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source_app="$script_dir/build/Codex Usage Bar.app"
destination="$HOME/Applications/Codex Usage Bar.app"
launch_agents_dir="$HOME/Library/LaunchAgents"
launch_agent="$launch_agents_dir/local.codex.usagebar.plist"
label=local.codex.usagebar

if [[ ! -x "$source_app/Contents/MacOS/CodexUsageBar" ]]; then
  "$script_dir/build.sh" >/dev/null
fi

mkdir -p "$HOME/Applications" "$launch_agents_dir" "$HOME/Library/Logs"
launchctl bootout "gui/$UID/$label" 2>/dev/null || true
ditto "$source_app" "$destination"

plist_temp=$(mktemp /tmp/codex-usagebar-launchagent.XXXXXX)
plutil -create xml1 "$plist_temp"
plutil -insert Label -string "$label" "$plist_temp"
plutil -insert ProgramArguments -array "$plist_temp"
plutil -insert ProgramArguments.0 -string "$destination/Contents/MacOS/CodexUsageBar" "$plist_temp"
plutil -insert RunAtLoad -bool true "$plist_temp"
plutil -insert KeepAlive -bool false "$plist_temp"
plutil -insert ProcessType -string Interactive "$plist_temp"
plutil -insert StandardOutPath -string "$HOME/Library/Logs/CodexUsageBar.log" "$plist_temp"
plutil -insert StandardErrorPath -string "$HOME/Library/Logs/CodexUsageBar.log" "$plist_temp"
mv "$plist_temp" "$launch_agent"

launchctl bootstrap "gui/$UID" "$launch_agent"
launchctl kickstart -k "gui/$UID/$label"
printf '已安装并启动：%s\n' "$destination"
