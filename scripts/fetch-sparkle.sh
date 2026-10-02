#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
DEST="$ROOT/.build/sparkle"
if [[ ! -d "$DEST/Sparkle.framework" ]]; then
  mkdir -p "$DEST"
  curl -fL https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$ROOT/.build/sparkle.tar.xz"
  echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  $ROOT/.build/sparkle.tar.xz" | shasum -a 256 -c -
  tar -xJf "$ROOT/.build/sparkle.tar.xz" -C "$DEST"
fi
