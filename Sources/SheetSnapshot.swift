import Foundation

struct SheetSnapshot: Codable {
    var version = 1
    var title: String
    var importedAt: Date
    var columns: [String]
    var rows: [[String]]
    static func parse(_ source: String, title: String) throws -> SheetSnapshot {
        let text = source.hasPrefix("\u{FEFF}") ? String(source.dropFirst()) : source
        guard !text.isEmpty else { throw DataError.invalid("表格是空的。") }
        let firstLine = text.prefix(while: { $0 != "\n" && $0 != "\r" })
        let delimiter: Character = firstLine.contains("\t") ? "\t" : ","
        let chars = Array(text)
        var result: [[String]] = [], row: [String] = [], cell = "", quoted = false, closedQuote = false, index = 0
        func endCell() { row.append(cell); cell = ""; closedQuote = false }
        func endRow() { endCell(); if row.contains(where: { !$0.isEmpty }) { result.append(row) }; row = [] }
        while index < chars.count {
            let c = chars[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { cell.append("\""); index += 1 }
                    else { quoted = false; closedQuote = true }
                } else { cell.append(c) }
            } else if c == delimiter { endCell() }
            else if c == "\n" || c == "\r" || c == "\r\n" {
                endRow()
                if c == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
            } else if c == "\"" && cell.isEmpty && !closedQuote { quoted = true }
            else if closedQuote { throw DataError.invalid("引号后的分隔格式有误，请重新导出 CSV 或 TSV。") }
            else { cell.append(c) }
            index += 1
        }
        guard !quoted else { throw DataError.invalid("表格中有未闭合的引号。") }
        if !cell.isEmpty || !row.isEmpty || closedQuote { endRow() }
        guard let columns = result.first, columns.count >= 2 else { throw DataError.invalid("请导入包含标题行和至少两列的 CSV / TSV 文件。") }
        guard columns.count <= 100, result.count <= 10001 else { throw DataError.invalid("此版本支持最多 100 列、10,000 条记录。") }
        let rows = Array(result.dropFirst())
        guard rows.allSatisfy({ $0.count <= columns.count }) else { throw DataError.invalid("存在比标题行更多的列，请确认首行为完整列名。") }
        let names = columns.enumerated().map { $0.element.trimmingCharacters(in: .whitespaces).isEmpty ? "未命名列 \($0.offset + 1)" : $0.element }
        return SheetSnapshot(title: title, importedAt: Date(), columns: names, rows: rows.map { $0 + Array(repeating: "", count: columns.count - $0.count) })
    }
}
