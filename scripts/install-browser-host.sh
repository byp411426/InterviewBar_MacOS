#!/bin/zsh
set -euo pipefail
APP="${1:-$HOME/Applications/面试日程.app}"
if [[ ! -x "$APP/Contents/MacOS/InterviewBarBridge" ]]; then
  print '未找到应用。请先安装，或将应用完整路径作为第一个参数传入。'; exit 1
fi
mkdir -p "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
DEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/app.interviewbar.macos.json"
FILE="$(mktemp "${TMPDIR:-/tmp}/interviewbar-host.XXXXXX")"
trap 'rm -f "$FILE"' EXIT
/usr/bin/plutil -create xml1 "$FILE"
/usr/bin/plutil -insert name -string app.interviewbar.macos "$FILE"
/usr/bin/plutil -insert description -string 'InterviewBar mail import bridge' "$FILE"
/usr/bin/plutil -insert path -string "$APP/Contents/MacOS/InterviewBarBridge" "$FILE"
/usr/bin/plutil -insert type -string stdio "$FILE"
/usr/bin/plutil -insert allowed_origins -json '["chrome-extension://coaablefbdodijhbjfecphakpbdompep/"]' "$FILE"
/usr/bin/plutil -convert json "$FILE"
chmod 600 "$FILE"
mv "$FILE" "$DEST"
print 'Chrome 本机连接已注册。请重新打开扩展面板，检查是否显示已连接。'
