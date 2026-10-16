#!/bin/sh
# Build a release zip containing only what WoW needs, in a folder named to match the .toc.
# Usage: tools/package.sh   (run from anywhere)
set -e
cd "$(dirname "$0")/.."
NAME=BBF_AnimatedPortraits
VERSION=$(sed -n 's/^## Version: *//p' "$NAME.toc" | tr -d '\r')
[ -n "$VERSION" ] || { echo "No ## Version in $NAME.toc" >&2; exit 1; }
STAGE=$(mktemp -d)
mkdir -p "$STAGE/$NAME" dist
cp "$NAME.toc" Core.lua LICENSE README.md CHANGELOG.md "$STAGE/$NAME/"
cp -R media "$STAGE/$NAME/"
OUT="$(pwd)/dist/$NAME-$VERSION.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qr -X "$OUT" "$NAME" -x '*.DS_Store')
rm -rf "$STAGE"
echo "Built $OUT"
