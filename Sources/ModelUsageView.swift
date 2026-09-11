import SwiftUI

struct ModelUsageView: View {
    @State private var records: [ModelUsageRecord] = []
    @State private var days = 7
    @State private var purpose = "全部"
    @State private var host = "全部服务"
    @State private var error = ""
    private let clock = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    private var filtered: [ModelUsageRecord] {
        let start = days == 0 ? Date.distantPast : Calendar.current.startOfDay(for: Date()).addingTimeInterval(-Double(days - 1) * 86400)
        return records.filter { $0.date >= start && (purpose == "全部" || $0.purpose.rawValue == purpose) && (host == "全部服务" || $0.host == host) }
    }
    private var summary: ModelUsageSummary { .init(records: filtered) }
    private func number(_ value: Int?) -> String { value.map { $0.formatted() } ?? "未提供" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("时间", selection: $days) { Text("今天").tag(1); Text("近 7 天").tag(7); Text("近 30 天").tag(30); Text("全部记录").tag(0) }.labelsHidden()
                Picker("用途", selection: $purpose) { Text("全部用途").tag("全部"); ForEach(ModelCallPurpose.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.labelsHidden()
                Picker("服务", selection: $host) { Text("全部服务").tag("全部服务"); ForEach(Array(Set(records.map(\.host))).sorted(), id: \.self) { Text($0).tag($0) } }.labelsHidden()
            }
            HStack(spacing: 10) {
                metric("网络请求", "\(summary.network.count) 次", "含失败和连接测试")
                metric("输入 Token", number(summary.sum(\.input)), "包含缓存输入")
                metric("输出 Token", number(summary.sum(\.output)), "以服务商返回为准")
            }
            HStack(spacing: 10) {
                metric("服务端缓存命中率", summary.cacheRate.map { String(format: "%.1f%%", $0 * 100) } ?? "未提供",
                    "\(summary.cacheReported.count)/\(summary.network.count) 次请求返回缓存信息")
                metric("缓存输入 Token", number(summary.sum(\.cached)), "已包含在输入中，不重复计数")
                metric("本机复用", "\(summary.localCount) 次", "未发请求，不新增 Token")
            }
            Text("命中率 = 已返回缓存信息的请求中，缓存输入 Token ÷ 输入 Token。未提供不等于 0；缺少用量的调用不会估填。金额暂不估算，以服务商账单为准。").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Text("最近调用").font(.headline); Spacer(); Text("时间 · 模型 / 用途 · 输入 / 输出 · 状态").font(.system(size: 10)).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        VStack(spacing: 8) { Image(systemName: "chart.bar.xaxis").font(.system(size: 28)); Text("还没有调用记录"); Text("先测试连接，或粘贴一封邮件开始识别。") }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(25)
                    }
                    ForEach(Array(filtered.reversed().prefix(100))) { record in
                        HStack(spacing: 12) {
                            Text(dateText(record.date, "MM-dd HH:mm")).font(.system(size: 11, design: .monospaced)).frame(width: 82, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.model).lineLimit(1)
                                Text(record.purpose.rawValue + (record.forced ? " · 跳过本机缓存" : "")).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(record.status == .local ? "— / —" : "\(number(record.tokens.input)) / \(number(record.tokens.output))").font(.system(size: 11, design: .monospaced))
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(record.status.rawValue).foregroundStyle(record.status == .failure ? Color.orange : accent)
                                Text(String(format: "%.1fs", record.seconds) + (record.httpStatus.map { " · \($0)" } ?? "")).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.frame(width: 80, alignment: .trailing)
                        }.font(.system(size: 12)).padding(.vertical, 9)
                        Divider()
                    }
                }
            }.frame(maxHeight: .infinity)
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            Text("仅统计本应用，自此版本开始记录；本机保留最近 10,000 条，列表显示筛选后最近 100 条。失败请求也可能产生费用，未知用量不算作零。").font(.system(size: 10)).foregroundStyle(.secondary)
        }.task { await refresh() }.onReceive(clock) { _ in Task { await refresh() } }
    }
    private func metric(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
    private func refresh() async {
        do { records = try await ModelUsageLedger.shared.snapshot(); error = await ModelUsageLedger.shared.writeWarning }
        catch { self.error = error.localizedDescription }
    }
}
