#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build
mkdir .build/local-release-lock || { echo 'Another release build is running.' >&2; exit 1; }
trap 'rmdir .build/local-release-lock' EXIT
swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP="$PWD/build/.releases.noindex/KeyFlip.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KeyboardSwitcher" "$APP/Contents/MacOS/KeyboardSwitcher"
cp scripts/update-app.sh "$APP/Contents/Resources/update-app.sh"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/make-icon.swift "$APP/Contents/Resources/Switcher.icns"
python3 - <<'PY'
from pathlib import Path
import plistlib
root = Path.cwd()
app = root/'build/.releases.noindex/KeyFlip.app'
info = app/'Contents/Info.plist'
counter = root/'.build/local-build-number'
previous = plistlib.loads(info.read_bytes()) if info.exists() else {}
number = max(int(previous.get('CFBundleVersion','10')), int(counter.read_text()) if counter.exists() else 10) + 1
counter.write_text(str(number))
values = dict(CFBundleExecutable='KeyboardSwitcher', CFBundleIdentifier='local.keyboard-switcher.app',
    CFBundleName='KeyFlip', CFBundleIconFile='Switcher.icns', CFBundlePackageType='APPL', CFBundleShortVersionString='0.4.0',
    CFBundleVersion=str(number), LSMinimumSystemVersion='13.0', LSUIElement=True, NSHighResolutionCapable=True,
    KSLocalUpdatePath=str(app),
    KSSigningRequirement='=anchor apple generic and identifier "local.keyboard-switcher.app" and certificate leaf[subject.OU] = "J4G38JM9GS"')
info.write_bytes(plistlib.dumps(values))
PY
codesign --force --sign "${KS_SIGN_IDENTITY:-36AFBC457010B5DE1159C7887C7802FF0F3B9D69}" "$APP"
requirement="$(/usr/libexec/PlistBuddy -c 'Print :KSSigningRequirement' "$APP/Contents/Info.plist")"
codesign --verify --deep --strict -R "$requirement" "$APP"
touch "$APP"
printf 'Built: %s\n' "$APP"
