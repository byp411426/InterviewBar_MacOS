import Foundation

func respond(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
    var count = UInt32(data.count).littleEndian
    FileHandle.standardOutput.write(Data(bytes: &count, count: 4))
    FileHandle.standardOutput.write(data)
}
func readExactly(_ count: Int) throws -> Data {
    var data = Data()
    while data.count < count {
        guard let chunk = try FileHandle.standardInput.read(upToCount: count - data.count), !chunk.isEmpty else { throw NSError(domain: "Incomplete request", code: 1) }
        data.append(chunk)
    }
    return data
}
do {
    let app = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let extensionID = try String(contentsOf: app.appendingPathComponent("Contents/Resources/extension-id.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard CommandLine.arguments.dropFirst().first == "chrome-extension://\(extensionID)/" else { throw NSError(domain: "扩展身份不匹配", code: 2) }
    let header = try readExactly(4)
    let size = header.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
    guard size > 0, size <= 200_000 else { throw NSError(domain: "文字内容超过大小限制", code: 3) }
    let data = try readExactly(size)
    guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NSError(domain: "请求格式无效", code: 4) }
    if message["action"] as? String == "ping" { respond(["ok": true, "version": "0.4.0"]); exit(0) }
    guard let text = message["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 60_000 else { throw NSError(domain: "请选择或粘贴邮件正文，最多约 2 万个汉字", code: 5) }
    let id = UUID()
    var safeURL = ""
    if var url = URLComponents(string: message["sourceURL"] as? String ?? ""), ["https", "http"].contains(url.scheme ?? "") {
        url.query = nil; url.fragment = nil; url.user = nil; url.password = nil
        safeURL = url.string ?? ""
    }
    let record: [String: Any] = ["id": id.uuidString, "text": text, "title": String((message["title"] as? String ?? "").prefix(300)), "sourceURL": safeURL, "capturedAt": Date().timeIntervalSinceReferenceDate]
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/InterviewBar/mail-inbox")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let file = directory.appendingPathComponent(id.uuidString + ".json")
    try JSONSerialization.data(withJSONObject: record).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", app.path, "interviewbar://import?id=\(id.uuidString)"]
    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "邮件已暂存，请先打开面试日程再重试", code: 6) }
    respond(["ok": true, "id": id.uuidString])
} catch {
    respond(["ok": false, "error": (error as NSError).domain])
}
