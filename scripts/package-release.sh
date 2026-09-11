#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
zsh build.sh
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw build/面试日程.app/Contents/Info.plist)"
ARCH="${INTERVIEWBAR_ARCH:-arm64}"
NAME="InterviewBar-v${VERSION}-macOS-${ARCH}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/interviewbar-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME/docs" "$STAGE/$NAME/scripts" dist
ditto build/面试日程.app "$STAGE/$NAME/面试日程.app"
cp README.md LICENSE "$STAGE/$NAME/"
cp docs/PRIVACY.md docs/NATIVE-WIDGETS.md docs/AI-SERVICES.md "$STAGE/$NAME/docs/"
cp scripts/install-browser-host.sh "$STAGE/$NAME/scripts/"
ditto BrowserExtension "$STAGE/$NAME/BrowserExtension"
python3 scripts/check-release.py "$STAGE"
ditto -c -k --keepParent --norsrc "$STAGE/$NAME" "dist/$NAME.zip"
(cd dist && shasum -a 256 "$NAME.zip" > SHA256SUMS.txt)
print "dist/$NAME.zip"
