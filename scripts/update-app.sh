#!/bin/bash
set -euo pipefail
candidate="$1"
destination="$2"
old_pid="$3"
requirement="$4"
no_launch="${5:-}"
launch_installed() {
  if [ "$no_launch" != '--no-launch' ]; then /usr/bin/open "$destination"; fi
}
log_dir="$HOME/Library/Logs/KeyboardSwitcher"
mkdir -p "$log_dir"
exec >> "$log_dir/update.log" 2>&1
trap 'status=$?; if [ -d "$destination" ]; then launch_installed || true; fi; exit "$status"' ERR
/usr/bin/codesign --verify --deep --strict -R "$requirement" "$candidate"
parent="$(dirname "$destination")"
mkdir -p "$parent"
staging="$(mktemp -d "$parent/.keyboard-switcher-update.XXXXXX")"
/usr/bin/ditto "$candidate" "$staging/next.app"
/usr/bin/codesign --verify --deep --strict -R "$requirement" "$staging/next.app"
if [ "$old_pid" -gt 0 ]; then
  for ((i=0; i<100; i++)); do
    if ! kill -0 "$old_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if kill -0 "$old_pid" 2>/dev/null; then
    rm -rf "$staging"
    exit 1
  fi
fi
rollback() {
  if [ -d "$staging/previous.app" ]; then
    if [ -d "$destination" ]; then mv "$destination" "$staging/failed.app"; fi
    mv "$staging/previous.app" "$destination"
    launch_installed || true
  fi
}
trap rollback ERR
if [ -e "$destination" ]; then mv "$destination" "$staging/previous.app"; fi
mv "$staging/next.app" "$destination"
/usr/bin/codesign --verify --deep --strict -R "$requirement" "$destination"
launch_installed
trap - ERR
# Keep the preceding signed version for manual recovery.
if [ -d "$staging/previous.app" ]; then
  backup="$HOME/Library/Application Support/KeyboardSwitcher"
  mkdir -p "$backup"
  if [ -d "$backup/Previous.app" ]; then rm -rf "$backup/Previous.app"; fi
  /usr/bin/ditto -c -k --keepParent "$staging/previous.app" "$backup/Previous.zip"
  rm -rf "$staging/previous.app"
fi
rmdir "$staging"
printf 'Installed %s at %s\n' "$destination" "$(date)"
