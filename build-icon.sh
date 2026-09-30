#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
mkdir -p "$PROJECT_DIR/Resources"
/Applications/Xcode.app/Contents/Developer/usr/bin/actool "$PROJECT_DIR/Post.icon" --compile "$PROJECT_DIR/Resources" --platform macosx --minimum-deployment-target 14.0 --app-icon Post --output-partial-info-plist "$PROJECT_DIR/Resources/IconInfo.plist" --target-device mac
