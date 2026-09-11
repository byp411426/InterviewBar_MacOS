import Foundation
@main struct SheetTests {
    static func main() throws {
        let csv = "\u{FEFF}公司,岗位,备注\r\n示例导航,软件工程师,\"一面,准备\n二面\"\r\n示例制造,,\"他说\"\"通过\"\"\"\r\n"
        let value = try SheetSnapshot.parse(csv, title: "test")
        assert(value.columns == ["公司", "岗位", "备注"])
        assert(value.rows.count == 2)
        assert(value.rows[0][2] == "一面,准备\n二面")
        assert(value.rows[1][2] == "他说\"通过\"")
        let tsv = try SheetSnapshot.parse("公司\t公司\t状态\n星河科技\t全栈\t\n", title: "test")
        assert(tsv.columns.count == 3 && tsv.rows[0] == ["星河科技", "全栈", ""])
        let short = try SheetSnapshot.parse("公司,岗位,状态\nA,B", title: "test")
        assert(short.rows[0] == ["A", "B", ""])
        for input in ["", "单列", "A,B\n1,2,3", "A,B\n\"unterminated", "A,B\n\"x\"oops,y"] {
            do { _ = try SheetSnapshot.parse(input, title: "test"); fatalError("Accepted invalid CSV") } catch {}
        }
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(SheetSnapshot.self, from: encoded)
        assert(decoded.rows == value.rows)
        print("PASS: CSV/TSV, BOM, CRLF, quotes, multiline cells, duplicate columns, blank fields, ragged-row normalization, malformed rejection, snapshot roundtrip")
    }
}
