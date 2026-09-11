# macOS 原生 WidgetKit 组件

## 当前状态

普通发行 ZIP 可直接使用“最近安排 / 本周统计”玻璃桌面面板（设置 → 桌面小组件）。这些面板由主应用管理，不是系统小组件库中的 WidgetKit 扩展。

`NativeWidgets/InterviewBarWidgets.swift` 实现了两个原生组件，支持 small / medium，在 macOS 14+ 的桌面和通知中心使用。源代码已针对 macOS 14 编译通过；当前开发机没有有效代码签名身份，因此**没有完成签名安装、系统组件库发现、实际共享容器读写和系统刷新验收**。不能仅凭编译成功宣称系统组件已经可用。

## 有开发者签名身份时构建

1. 准备有效的 Apple Development 或 Developer ID Application 签名证书及其私钥，并安装到本机钥匙串。可使用 Xcode 登录自己的开发者账号管理证书；不要把私钥交给他人或上传本项目。
2. 用 `security find-identity -v -p codesigning` 查看本机有效签名身份，确认自己的 Team ID。没有有效身份时先完成开发者签名配置。
3. 在仓库根目录运行以下命令，把占位值换成自己的身份名称和 Team ID；这些值是签名身份名称，不是 API 密钥。

```sh
INTERVIEWBAR_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
INTERVIEWBAR_TEAM_ID='YOURTEAMID' \
zsh scripts/build-native-widgets.sh
```

4. 脚本先构建主应用，再编译扩展到 `Contents/PlugIns/InterviewBarWidgets.appex`，用同一身份签名主应用与扩展，配置 `<TeamID>.app.interviewbar.shared` 共享组。扩展启用 App Sandbox，仅从组容器读快照。
5. 把 `build/面试日程.app` 安装到应用程序文件夹，打开一次，创建或更新一条自己的安排。
6. 桌面右键 → “编辑小组件”，搜索“面试日程”，选择“最近安排”或“本周统计”。通知中心也可添加。没有出现时需要检查系统扩展加载与签名日志，当前项目尚未在真实签名环境完成这一步。
7. 确认倒计时、跨周统计、点击打开主应用，以及修改日程后的刷新。WidgetKit 的刷新由系统调度，不保证每秒重新读取数据；倒计时使用系统日期视图，时间轴包含下一项切换节点。

脚本没有自动执行 Apple 公证。普通 `build.sh` 和 `package-release.sh` 会生成不带原生扩展的临时签名版本；开发者要分发原生版，应对签名安装和公证另行验收后再打包，不能用普通打包脚本覆盖该产物。

## 数据边界

原生版通过本机 App Group 共享 `widget-snapshot.json`，只含未来待办的公司/类型/时间、完成日期及同步时间，不共享 API 密钥、邮件原文、会议链接或投递总表。主应用写入后请求 WidgetKit 刷新；主应用退出时，原生组件继续使用最后一次快照，不能获知尚未同步的新修改。

不要提交共享容器、签名私钥、个人配置或数据快照。系统组件的背景与透明效果由 macOS 决定，与自由浮动面板的玻璃材质不完全相同。

依据：[Apple WidgetKit](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)、[App Groups 配置](https://developer.apple.com/documentation/xcode/configuring-app-groups)。macOS 支持以开发者 Team ID 为前缀的组名，并核对访问进程的签名团队。
