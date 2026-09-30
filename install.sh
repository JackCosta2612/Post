#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
SOURCE_APP="${POST_APP_OUTPUT:-$PROJECT_DIR/../Post.app}"
DESTINATION="/Applications/Post.app"
if pgrep -x Post >/dev/null; then
  echo "Quit Post before installing the update."
  exit 1
fi
codesign --verify --strict "$SOURCE_APP"
if [[ -e "$DESTINATION" ]]; then
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
  if [[ "$BUNDLE_ID" != "com.jack.Post" ]]; then echo "Another app occupies $DESTINATION"; exit 1; fi
fi
ditto "$SOURCE_APP" "$DESTINATION"
codesign --verify --strict "$DESTINATION"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINATION"
echo "Installed and registered $DESTINATION"
