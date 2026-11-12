#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/.releases.noindex/KeyFlip.app"
[ -d "$APP" ] || { echo 'Run bash scripts/build.sh first.' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
package_dir="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
ditto "$APP" "$package_dir/KeyFlip.app"
ln -s /Applications "$package_dir/Applications"
cat > "$package_dir/Установка.txt" <<'TEXT'
Перетащи KeyFlip.app в Applications и запусти из Программ.
Разреши Accessibility и Input Monitoring в Privacy & Security.
Автозапуск включается в меню ⇄ → Запускать при входе.
Для обновления: ⇄ → Установить локальное обновление…
Эта локальная сборка получает обновления из проекта на этом Mac.
TEXT
hdiutil create -volname 'KeyFlip' -srcfolder "$package_dir" -format UDZO -ov "$PWD/build/KeyFlip.dmg"
hdiutil verify "$PWD/build/KeyFlip.dmg"
