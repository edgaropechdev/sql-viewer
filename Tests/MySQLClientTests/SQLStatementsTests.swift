import Testing
@testable import MySQLClient

@Suite struct SQLStatementsTests {
    @Test func splitsOnSemicolons() {
        #expect(SQLStatements.statements(in: "SELECT 1; SELECT 2;\n  SELECT 3") == ["SELECT 1", "SELECT 2", "SELECT 3"])
    }

    @Test func ignoresDelimitersInsideQuotesAndComments() {
        let sql = """
        SELECT 'a;b', "c;d", `e;f`; -- x; y
        SELECT 'it''s; fine', 'back\\';slash' # z;
        ; /* a; b */ SELECT 3
        """
        #expect(SQLStatements.statements(in: sql) == [
            "SELECT 'a;b', \"c;d\", `e;f`",
            "-- x; y\nSELECT 'it''s; fine', 'back\\';slash' # z;",
            "/* a; b */ SELECT 3",
        ])
    }

    @Test func doubleDashNeedsTrailingWhitespace() {
        #expect(SQLStatements.statements(in: "SELECT 5--1; SELECT 2") == ["SELECT 5--1", "SELECT 2"])
    }

    @Test func skipsCommentOnlySegments() {
        #expect(SQLStatements.statements(in: "SELECT 1;\n-- trailing note\n") == ["SELECT 1"])
    }

    @Test func picksStatementUnderCursor() {
        let sql = "SELECT 1;\nSELECT 2;\n\n"
        #expect(SQLStatements.range(at: 3, in: sql) == 0..<8)
        #expect(SQLStatements.range(at: 9, in: sql) == 0..<8)  // right after `;`
        #expect(SQLStatements.range(at: 12, in: sql) == 10..<18)
        #expect(SQLStatements.range(at: 21, in: sql) == 10..<18)  // past the end
        #expect(SQLStatements.range(at: 0, in: "  \n") == nil)
    }

    @Test func offsetsAreUTF16() {
        let sql = "SELECT '🙂'; SELECT 2"
        #expect(SQLStatements.ranges(in: sql) == [0..<11, 13..<21])
    }

    @Test func quotesIdentifiers() {
        #expect(quoteIdentifier("we`ird") == "`we``ird`")
    }
}
