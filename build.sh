#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/面试日程.app"
BUNDLE_ID="${INTERVIEWBAR_BUNDLE_ID:-app.interviewbar.macos}"
ARCH="${INTERVIEWBAR_ARCH:-arm64}"
rm -rf "$APP/Contents/PlugIns/InterviewBarWidgets.appex"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target "$ARCH-apple-macosx13.0" -debug-prefix-map "$PWD=/InterviewBar" Sources/*.swift -o "$APP/Contents/MacOS/InterviewBar" -framework AppKit -framework SwiftUI -framework UserNotifications -framework WebKit -framework ServiceManagement
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>InterviewBar</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>面试日程</string>
<key>CFBundleDisplayName</key><string>面试日程</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.10.1</string>
<key>CFBundleVersion</key><string>14</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Mail import</string><key>CFBundleURLSchemes</key><array><string>interviewbar</string></array></dict></array>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc -O -target "$ARCH-apple-macosx13.0" -debug-prefix-map "$PWD=/InterviewBar" NativeHost/main.swift -o "$APP/Contents/MacOS/InterviewBarBridge"
cp BrowserExtension/extension-id.txt "$APP/Contents/Resources/extension-id.txt"
codesign --force --sign - "$APP/Contents/MacOS/InterviewBarBridge"
codesign --force --sign - "$APP"
print "$APP"
