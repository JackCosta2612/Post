#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
# Use the configured toolchain. The installed command-line tools can build this app.
APP_DIR="${POST_APP_OUTPUT:-$PROJECT_DIR/../Post.app}"
if [[ "${POST_DEMO_BUILD:-0}" == "1" ]]; then APP_DIR="$PROJECT_DIR/.build/Post Demo.app"; fi
BUILD_DIR="$PROJECT_DIR/.build"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="${POST_ARCH:-$(uname -m)}"
"$PROJECT_DIR/scripts/fetch-sparkle.sh"
xcrun swiftc -swift-version 5 -O -parse-as-library -module-name Post -module-cache-path "$BUILD_DIR/module-cache" -sdk "$SDK_PATH" -target "$ARCH-apple-macos14.0" "$PROJECT_DIR"/Sources/*.swift -F "$BUILD_DIR/sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$APP_DIR/Contents/MacOS/Post"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
RELEASE_VERSION="$(tr -d '\n' < "$PROJECT_DIR/VERSION")"
if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Invalid VERSION"; exit 1; fi
BUILD_NUMBER="$(git -C "$PROJECT_DIR" rev-list --count HEAD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
if [[ "${POST_DEMO_BUILD:-0}" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.jack.Post.demo" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Post Demo" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Post Demo" "$APP_DIR/Contents/Info.plist"
fi
mkdir -p "$APP_DIR/Contents/Frameworks"
ditto "$BUILD_DIR/sparkle/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$PROJECT_DIR/RELEASE_NOTES.md" "$APP_DIR/Contents/Resources/ReleaseNotes.md"
cp "$PROJECT_DIR/Setup.md" "$APP_DIR/Contents/Resources/Setup.md"
cp "$PROJECT_DIR/Resources/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
cp "$PROJECT_DIR/Resources/Post.icns" "$APP_DIR/Contents/Resources/Post.icns"
SIGNING_NAME="${POST_SIGNING_IDENTITY:-Post Local Development}"
if [[ "$SIGNING_NAME" == "-" ]]; then
  codesign --force --sign - "$APP_DIR"
elif security find-certificate -c "$SIGNING_NAME" >/dev/null 2>&1; then
  codesign --force --sign "$SIGNING_NAME" "$APP_DIR"
else
  echo "No local signing certificate. Run ./setup-signing.sh first."
  echo "For a disposable preview build: POST_SIGNING_IDENTITY=- ./build.sh"
  exit 1
fi
echo "Built $APP_DIR"
