# README 截图维护

运行 `python3 scripts/screenshots/render.py`，将用本项目真实 SwiftUI 界面渲染四张 PNG 到 `docs/images/`。需要 macOS 和 Swift 编译工具。

为避免泄露个人信息，脚本只在 `build/documentation-screenshots/` 生成源文件副本，将模型配置、邮件识别结果和用量页替换为 `Render.swift` 内的虚构演示状态。日程库使用临时目录，运行后删除；不改正式源码，不启动或修改个人安装的应用，不读取个人日程库、钥匙串，也不调用模型 API。

这些是实际应用视图的文档渲染图；识别字段与 Token 数是固定演示数据，不是一次真实模型调用的证明。README 图下注明此点。布局直接复用正式界面，更新截图时须逐张检查裁切、文字、空状态和隐私。

图片对应：

- `ai-configuration.png`：服务商、地址、模型、空密钥框、测试连接与保存。
- `ai-usage.png`：Token、服务端缓存、本机复用、用途筛选及最近调用。
- `mail-recognition.png`：虚构邮件原文及校对结果。
- `journey-statistics.png`：虚构已完成安排的每周统计图。
