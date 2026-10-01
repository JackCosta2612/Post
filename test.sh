#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
mkdir -p "$BUILD_DIR/module-cache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD_DIR/module-cache" -sdk "$SDK_PATH" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/Gmail.swift" "$PROJECT_DIR/Sources/MailStore.swift" "$PROJECT_DIR/Tests/BehaviorTests.swift" -o "$BUILD_DIR/PostTests"
"$BUILD_DIR/PostTests"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD_DIR/module-cache" -sdk "$SDK_PATH" "$PROJECT_DIR/Sources/Models.swift" "$PROJECT_DIR/Sources/Gmail.swift" "$PROJECT_DIR/Tests/GmailTests.swift" -o "$BUILD_DIR/GmailTests"
"$BUILD_DIR/GmailTests"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD_DIR/module-cache" -sdk "$SDK_PATH" "$PROJECT_DIR/Sources/Updates.swift" "$PROJECT_DIR/Tests/VersionTests.swift" -o "$BUILD_DIR/VersionTests"
"$BUILD_DIR/VersionTests"
