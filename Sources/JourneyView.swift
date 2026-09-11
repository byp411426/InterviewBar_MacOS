import SwiftUI

struct JourneyView: View {
    @ObservedObject var store: EventStore
    let edit: (InterviewEvent?) -> Void
    @State private var kind = EventKindFilter.all
    @State private var quote = JourneyStats.nextEncouragement()
    @State private var completedOnly = false
    var events: [InterviewEvent] { store.events.filter { kind.matches($0.kind) && (!completedOnly || $0.status == .completed) } }
    var completed: [InterviewEvent] { store.events.filter { $0.status == .completed } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("我的秋招之旅").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("每一次认真准备，都值得留下一笔。").foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(completed.count)").font(.system(size: 36, weight: .medium, design: .monospaced)).foregroundStyle(accent)
                    Text("次已完成安排").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 20)
            HStack(spacing: 24) {
                ForEach(EventKind.allCases, id: \.self) { type in
                    Label("\(type.rawValue)  \(completed.filter { $0.kind == type }.count)", systemImage: type.symbol).foregroundStyle(type.tint)
                }
            }.font(.system(size: 13, weight: .medium)).padding(.bottom, 18)
            HStack(alignment: .top) {
                Image(systemName: "leaf").foregroundStyle(accent)
                Text(quote).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("换一句") { quote = JourneyStats.nextEncouragement(excluding: quote) }.buttonStyle(.plain).foregroundStyle(accent)
            }.padding(16).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Picker("类型", selection: $kind) { ForEach(EventKindFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 180)
                Toggle("只看已完成", isOn: $completedOnly)
                Spacer()
                Text("\(store.unscheduled.count) 项时间待通知").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if events.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("旅程从一条记录开始").font(.title3)
                            Text("添加安排，完成后标记“已完成”。记录会一直留在这里，等待以后回看。").foregroundStyle(.secondary)
                            Button("添加安排") { edit(nil) }
                        }.padding(.vertical, 30)
                    }
                    ForEach(JourneyStats.weeks(events)) { week in
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 0) {
                                Circle().fill(accent).frame(width: 9, height: 9)
                                Rectangle().fill(accent.opacity(0.18)).frame(width: 1).frame(maxHeight: .infinity)
                            }.frame(width: 12).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(dateText(week.start, "yyyy.MM.dd") + " — " + dateText(week.end, "MM.dd")).font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    Spacer()
                                    Text("完成 \(week.completed.count) / \(week.events.count) 项").font(.caption).foregroundStyle(accent)
                                }
                                Text(EventKind.allCases.map { "\($0.rawValue) \(week.count($0))" }.joined(separator: "   ·   ")).font(.caption).foregroundStyle(.secondary)
                                ForEach(week.events) { event in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(dateText(event.date, "E HH:mm")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 85, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Button(event.company) { edit(event) }.buttonStyle(.plain).font(.system(size: 14, weight: .medium))
                                            Text(event.kindLabel + (event.isDeadline ? " · 截止" : "") + (event.role.isEmpty ? "" : " · " + event.role)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Menu {
                                            Button("编辑安排") { edit(event) }
                                            Button("标记已完成") { store.setStatus(event, .completed) }
                                            Button("恢复待办") { store.setStatus(event, .pending) }
                                            Button("取消安排") { store.setStatus(event, .cancelled) }
                                        } label: {
                                            Text(event.overdue(at: store.now) ? "已过时间 · 待确认" : event.status.rawValue)
                                                .foregroundStyle(event.status == .completed ? accent : Color.secondary)
                                        }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(event.company + "旅程状态")
                                    }.padding(.vertical, 7)
                                    Divider()
                                }
                            }
                        }
                    }
                }.padding(.vertical, 20)
            }
            Divider()
            Text("北京时间 · 每周一至周日，按安排日期归周。仅“已完成”计入次数；过期不会自动删除或计为完成。未通过不代表没有付出，次数也不定义你的价值。")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(minWidth: 720, minHeight: 530)
        .alert("保存提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("好") { store.error = nil } } message: { Text(store.error ?? "") }
    }
}
