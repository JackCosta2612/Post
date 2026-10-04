#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
VERSION="$(cat "$ROOT/VERSION")"
OUT="$ROOT/.build/updates"
mkdir -p "$OUT" "$ROOT/.build/intel"
POST_ARCH=arm64 POST_APP_OUTPUT="$ROOT/.build/updates/Post.app" "$ROOT/build.sh"
POST_ARCH=x86_64 POST_APP_OUTPUT="$ROOT/.build/intel/Post.app" "$ROOT/build.sh"
lipo -create "$OUT/Post.app/Contents/MacOS/Post" "$ROOT/.build/intel/Post.app/Contents/MacOS/Post" -output "$OUT/Post.app/Contents/MacOS/Post.universal"
mv "$OUT/Post.app/Contents/MacOS/Post.universal" "$OUT/Post.app/Contents/MacOS/Post"
codesign --force --sign "${POST_SIGNING_IDENTITY:-Post Local Development}" "$OUT/Post.app"
codesign --verify --deep --strict "$OUT/Post.app"
ditto -c -k --sequesterRsrc --keepParent "$OUT/Post.app" "$OUT/Post-v$VERSION.zip"
cp "$ROOT/RELEASE_NOTES.md" "$OUT/Post-v$VERSION.md"
"$ROOT/.build/sparkle/bin/generate_appcast" --account com.jack.Post.updates --maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/JackCosta2612/Post/releases/download/v$VERSION/" "$OUT"
# Each retained archive belongs to its own release, including older feed entries.
python3 - "$OUT/appcast.xml" <<'FEED'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
p.write_text(re.sub(r'https://github.com/JackCosta2612/Post/releases/download/v[^/]+/(Post-v([^/"\s]+)\.zip)', lambda m: 'https://github.com/JackCosta2612/Post/releases/download/v' + m[2] + '/' + m[1], p.read_text()))
FEED
cp "$OUT/appcast.xml" "$ROOT/docs/appcast.xml"
echo "Signed update: $OUT/Post-v$VERSION.zip"
