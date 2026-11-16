#!/bin/zsh
# Builds "Amazing Info News.app" (Apple silicon + Intel) next to this script.
#   ./build.sh            build the app
#   ./build.sh --package  also make "Ai.N for Mac.zip" to email
set -euo pipefail
cd "$(dirname "$0")"

APP="Amazing Info News.app"
VERSION=1.4

echo "Building for Apple silicon…"
swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build-arm64 >/dev/null
echo "Building for Intel…"
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86_64 >/dev/null

rm -rf AmazingNews.app "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARM=$(swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build-arm64 --show-bin-path)
X86=$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86_64 --show-bin-path)
lipo -create "$ARM/AmazingNews" "$X86/AmazingNews" -output "$APP/Contents/MacOS/AmazingNews"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Amazing Info News</string>
  <key>CFBundleDisplayName</key><string>Amazing Info News</string>
  <key>CFBundleIdentifier</key><string>com.millwoodpictures.amazingnews</string>
  <key>CFBundleExecutable</key><string>AmazingNews</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.news</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Millwood Pictures Inc.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/AmazingNews"))"

if [[ "${1:-}" == "--package" ]]; then
  STAGE=$(mktemp -d)
  mkdir -p "$STAGE/Ai.N"
  ditto "$APP" "$STAGE/Ai.N/$APP"
  cp "Install Ai.N.txt" "$STAGE/Ai.N/"
  rm -f "Ai.N for Mac.zip"
  ditto -c -k --norsrc --noextattr --keepParent "$STAGE/Ai.N" "Ai.N for Mac.zip"
  rm -rf "$STAGE"
  echo "Packaged $(pwd)/Ai.N for Mac.zip ($(du -h "Ai.N for Mac.zip" | cut -f1))"
fi
