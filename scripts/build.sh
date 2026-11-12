#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f scripts/signing.local.sh ]; then source scripts/signing.local.sh; fi
: "${KS_SIGN_IDENTITY:?Set KS_SIGN_IDENTITY or copy scripts/signing.example.sh to scripts/signing.local.sh}"
: "${KS_SIGN_TEAM:?Set KS_SIGN_TEAM to your Apple signing Team ID}"
export KS_SIGN_IDENTITY KS_SIGN_TEAM
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
import plistlib, os
root = Path.cwd()
app = root/'build/.releases.noindex/KeyFlip.app'
info = app/'Contents/Info.plist'
counter = root/'.build/local-build-number'
previous = plistlib.loads(info.read_bytes()) if info.exists() else {}
number = max(int(previous.get('CFBundleVersion','10')), int(counter.read_text()) if counter.exists() else 10) + 1
counter.write_text(str(number))
values = dict(CFBundleExecutable='KeyboardSwitcher', CFBundleIdentifier='local.keyboard-switcher.app',
    CFBundleName='KeyFlip', CFBundleIconFile='Switcher.icns', CFBundlePackageType='APPL', CFBundleShortVersionString='0.5.2',
    CFBundleVersion=str(number), LSMinimumSystemVersion='13.0', LSUIElement=True, NSHighResolutionCapable=True,
    KSLocalUpdatePath=str(app),
    KSSigningRequirement='=anchor apple generic and identifier "local.keyboard-switcher.app" and certificate leaf[subject.OU] = "' + os.environ['KS_SIGN_TEAM'] + '"' )
info.write_bytes(plistlib.dumps(values))
PY
codesign --force --sign "${KS_SIGN_IDENTITY}" "$APP"
requirement="$(/usr/libexec/PlistBuddy -c 'Print :KSSigningRequirement' "$APP/Contents/Info.plist")"
codesign --verify --deep --strict -R "$requirement" "$APP"
touch "$APP"
printf 'Built: %s\n' "$APP"
