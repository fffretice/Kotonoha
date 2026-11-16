#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p work/build work/clang-cache outputs
# Some CLT upgrades leave a duplicate SwiftBridging module map. Apply a build-only
# overlay in that case; never modify the installed toolchain.
python3 - <<'PYBUILD'
import os,json
old='/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap'
new='/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap'
open('work/empty.modulemap','w').close()
roots=[]
if os.path.isfile(old) and os.path.isfile(new):
 roots=[{'type':'file','name':old,'external-contents':os.path.abspath('work/empty.modulemap')}]
json.dump({'version':0,'roots':roots},open('work/toolchain-overlay.json','w'))
PYBUILD
export CLANG_MODULE_CACHE_PATH="$PWD/work/clang-cache"
# Build with the system Swift compiler; full Xcode is not required.
swiftc -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/work/toolchain-overlay.json" -O -swift-version 5 -parse-as-library -emit-module -emit-library -static -module-name TranslationCore -emit-module-path work/build/TranslationCore.swiftmodule Sources/TranslationCore/*.swift -o work/build/libTranslationCore.a
swiftc -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/work/toolchain-overlay.json" -O -swift-version 5 -parse-as-library -I work/build work/build/libTranslationCore.a Sources/Kotonoha/*.swift -o work/build/Kotonoha
swiftc -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/work/toolchain-overlay.json" -O -swift-version 5 -parse-as-library Sources/KotonohaFixture/*.swift -o work/build/KotonohaFixture
swiftc -target arm64-apple-macosx14.0 -vfsoverlay "$PWD/work/toolchain-overlay.json" scripts/CloseKotonoha.swift -o work/build/close-kotonoha
STAGING="$PWD/work/staging-$(date +%s)"
APP="$STAGING/言叶 Kotonoha.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp work/build/Kotonoha "$APP/Contents/MacOS/Kotonoha"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/使用说明.txt "$APP/Contents/Resources/使用说明.txt"
cp LICENSE NOTICE THIRD_PARTY.md "$APP/Contents/Resources/"
if [[ -d work/runtime ]]; then
  mkdir -p "$APP/Contents/Resources/Runtime"
  cp -R work/runtime/. "$APP/Contents/Resources/Runtime/"
fi
DEMO="$APP/Contents/Resources/试读场景.app"
mkdir -p "$DEMO/Contents/MacOS"
cp work/build/KotonohaFixture "$DEMO/Contents/MacOS/KotonohaFixture"
cat > "$DEMO/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.kotonoha.fixture</string><key>CFBundleExecutable</key><string>KotonohaFixture</string><key>CFBundleName</key><string>试读场景</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
if [[ -d "$PWD/outputs/言叶 Kotonoha.app" ]]; then
  mv "$PWD/outputs/言叶 Kotonoha.app" "$PWD/work/previous-app-$(date +%s).app"
fi
mv "$APP" "$PWD/outputs/言叶 Kotonoha.app"
rmdir "$STAGING"
print "Built: $PWD/outputs/言叶 Kotonoha.app"
