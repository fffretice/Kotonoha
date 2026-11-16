#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/outputs/言叶 Kotonoha.app"
STAGE="$PWD/work/dmg-root-$(date +%s)"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$PWD/outputs/Kotonoha-${VERSION}-AppleSilicon.dmg"
mkdir -p "$STAGE"
# Every run uses a new app inode; never mutate the signed bundle.
if [[ -d "$STAGE/言叶 Kotonoha.app" ]]; then mv "$STAGE/言叶 Kotonoha.app" "$PWD/work/dmg-previous-$(date +%s).app"; fi
ditto "$APP" "$STAGE/言叶 Kotonoha.app"
[[ -L "$STAGE/Applications" ]] || ln -s /Applications "$STAGE/Applications"
cp Resources/UserGuide.txt "$STAGE/Read me.txt"
cp THIRD_PARTY.md "$STAGE/THIRD_PARTY.md"
cp LICENSE NOTICE "$STAGE/"
python3 - <<'PY'
from pathlib import Path
root=Path('work/dmg-root')
weights=[p for p in root.rglob('*') if p.is_file() and p.suffix.lower() in ['.gguf','.safetensors','.bin']]
assert not weights, weights
size=sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
assert size < 100*1024*1024, size
print('Verified: no model weights; package contents',round(size/1024/1024,1),'MiB')
PY
codesign --verify --deep --strict "$STAGE/言叶 Kotonoha.app"
hdiutil create -volname '言叶 Kotonoha' -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
