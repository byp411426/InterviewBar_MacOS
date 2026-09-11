#!/bin/zsh
# Optional signed WidgetKit build; never embeds developer credentials in source.
set -euo pipefail
cd "${0:A:h:h}"
: "${INTERVIEWBAR_SIGN_IDENTITY:?请设置有效的 Apple Development 或 Developer ID Application 签名身份名称}"
: "${INTERVIEWBAR_TEAM_ID:?请设置你的 10 位 Apple Developer Team ID}"
if [[ ! "$INTERVIEWBAR_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]]; then
  print 'Team ID 格式无效。'; exit 1
fi
zsh build.sh
APP="$PWD/build/面试日程.app"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")"
GROUP="$INTERVIEWBAR_TEAM_ID.app.interviewbar.shared"
EXT="$APP/Contents/PlugIns/InterviewBarWidgets.appex"
ARCH="${INTERVIEWBAR_ARCH:-arm64}"
mkdir -p "$EXT/Contents/MacOS"
swiftc -D WIDGET_EXTENSION -application-extension -parse-as-library -O -swift-version 5 -target "$ARCH-apple-macosx14.0" -debug-prefix-map "$PWD=/InterviewBar" Sources/WidgetData.swift NativeWidgets/InterviewBarWidgets.swift -o "$EXT/Contents/MacOS/InterviewBarWidgets" -framework SwiftUI -framework WidgetKit
python3 - "$APP" "$BUNDLE_ID" "$GROUP" "$INTERVIEWBAR_TEAM_ID" <<'PY'
from pathlib import Path
import plistlib,sys
app=Path(sys.argv[1]); bundle,group,team=sys.argv[2:]
plist=app/'Contents/Info.plist'
v=plistlib.loads(plist.read_bytes()); v['InterviewBarWidgetGroup']=group; v['LSMinimumSystemVersion']='14.0'; plist.write_bytes(plistlib.dumps(v))
ext=app/'Contents/PlugIns/InterviewBarWidgets.appex/Contents/Info.plist'
ext.write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle+'.widgets','CFBundleExecutable':'InterviewBarWidgets','CFBundleName':'面试日程','CFBundleDisplayName':'面试日程','CFBundlePackageType':'XPC!','CFBundleShortVersionString':v['CFBundleShortVersionString'],'CFBundleVersion':v['CFBundleVersion'],'LSMinimumSystemVersion':'14.0','InterviewBarWidgetGroup':group,'NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}))
for name,identifier,sandbox in [('app',bundle,False),('widget',bundle+'.widgets',True)]:
 ent={'com.apple.security.application-groups':[group],'com.apple.developer.team-identifier':team,'com.apple.application-identifier':team+'.'+identifier}
 if sandbox: ent['com.apple.security.app-sandbox']=True
 Path('build/'+name+'-widget.entitlements').write_bytes(plistlib.dumps(ent))
PY
codesign --force --options runtime --sign "$INTERVIEWBAR_SIGN_IDENTITY" "$APP/Contents/MacOS/InterviewBarBridge"
codesign --force --options runtime --entitlements build/widget-widget.entitlements --sign "$INTERVIEWBAR_SIGN_IDENTITY" "$EXT"
codesign --force --options runtime --entitlements build/app-widget.entitlements --sign "$INTERVIEWBAR_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
print '原生 WidgetKit 扩展已构建并签名。安装应用并打开一次，再进入系统“编辑小组件”添加。此脚本不会自动完成 Apple 公证。'
