# AI 服务与用量

## 统一请求层的范围

应用借鉴“统一配置 + 逐次记账”的交互思路，在程序内部集中处理模型请求。没有监听网络端口，没有接管其他软件的代理，也不会读取 CC Switch 的配置或凭据。可参考 [CC Switch 官方用量说明](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/en/4-proxy/4.4-usage.md)；本项目独立实现，不包含其代码。

## 兼容方式与官方依据

按 2026-09-11 可查阅的官方说明配置：

| 服务 | 请求差异 | 缓存统计读取 |
| --- | --- | --- |
| DeepSeek | `thinking.type = disabled`，JSON 输出 | `prompt_cache_hit_tokens`，或输入详情的 `cached_tokens` |
| 千问 | 顶层 `enable_thinking = false`，JSON 输出 | `prompt_tokens_details.cached_tokens` |
| Kimi | `thinking.type = disabled`；不强制温度；默认关闭强制 JSON 参数 | `cached_tokens` 或输入详情的 `cached_tokens` |
| GLM | `thinking.type = disabled`，JSON 输出 | `prompt_tokens_details.cached_tokens` |
| 自定义 | 根据模型名前缀适配上面的系列；其他模型不添加思考参数 | 兼容以上 usage 字段 |

接口兼容仅指 Chat Completions；不支持直接填写 Anthropic Messages、Gemini GenerateContent 等专用协议地址。默认不做失败后自动重试，以免重复计费。不跟随 HTTP 重定向，密钥不会被自动转发到新地址。

官方资料：

- [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)、[价格与模型信息](https://api-docs.deepseek.com/quick_start/pricing/)
- [千问兼容接口](https://help.aliyun.com/en/model-studio/qwen-api-via-openai-chat-completions)、[上下文缓存](https://help.aliyun.com/en/model-studio/context-cache)
- [Kimi K2.6 指南](https://platform.kimi.com/docs/guide/kimi-k2-6-quickstart)、[Chat 接口](https://platform.kimi.com/docs/api/chat)
- [GLM-4.7-Flash](https://docs.bigmodel.cn/cn/guide/models/free/glm-4.7-flash)、[思考模式](https://docs.bigmodel.cn/cn/guide/capabilities/thinking-mode)、[缓存](https://docs.bigmodel.cn/cn/guide/capabilities/cache)

这里的模型名是可编辑预设，不会自动查询或替换用户模型。服务商可能变更名称、权限与参数；如果返回不支持的参数，可关闭 JSON 要求或填写该服务支持的模型。仅 DeepSeek 完成真实账号验证，其余三家通过请求 / 响应模拟验证。

## 如何理解用量

每次实际网络请求单独记账。输入取 `usage.prompt_tokens`，输出取 `completion_tokens`，总量取 `total_tokens`，或在前两项均已知时相加。缓存输入本身就是输入的一部分。服务商未返回任何用量、网络在响应前中断等情况，均保留未知，不计为零。

服务端缓存命中率按 Token 加权，而非逐条百分比的平均值：

```
报告了缓存信息的请求，其缓存输入 Token 总和
÷ 同一批请求的输入 Token 总和
```

例如两次请求分别输入 100、900 Token，缓存命中 100、0 Token，总命中率是 10%，不是 50%。另一次请求如果没有返回缓存字段，不放进上述分母，页面展示报告覆盖次数。输入总量为零时没有可计算的比例。

本机复用是另一件事：相同正文、参考日期、接口、模型及参数的成功结果在内存中保留最多 10 分钟、最多 20 条；复用时没有 API 请求。重新识别与连接测试跳过本机复用；连接测试不会覆盖邮件识别缓存。退出应用或更改配置会清空内存缓存。

短邮件内容经常不同，不一定能达到服务商的最小缓存长度。固定字段提取提示放在消息前部有利于前缀复用，但是否命中仍由服务商决定，应用不伪造命中或承诺比例。

## 数据与费用边界

- 时间筛选、用途筛选和服务域名筛选同时作用于上方统计及明细。界面日期按当前 Mac 日历日筛选。
- 仅汇总已经返回的数值，可能低于实际账单；失败 / 取消请求同样可能计费。
- 只保留最近 10,000 条本应用操作，明细一次显示最近 100 条；“全部记录”指保留的记录，不是账号全历史。
- 不读取账号余额，不估算人民币 / 美元费用。缓存价格、模型版本、地域、时段和套餐会影响实际费用，以服务商账单为准。
- 本机使用记录不上传 GitHub、不发送给模型。详见 [隐私说明](PRIVACY.md)。
