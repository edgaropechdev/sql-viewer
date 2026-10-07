/// Splits SQL text into statements on `;`, honoring quotes and comments.
///
/// Offsets are UTF-16 code units so they map directly onto `NSString` /
/// `NSTextView` ranges. The client-side `DELIMITER` command is not supported.
public enum SQLStatements {
    struct Segment {
        /// Statement text without the delimiter or surrounding whitespace.
        var range: Range<Int>
        /// End of the segment including its `;`, used for cursor hit-testing.
        var end: Int
        /// False when the segment holds only whitespace and comments.
        var hasCode: Bool
    }

    public static func ranges(in text: String) -> [Range<Int>] {
        segments(in: Array(text.utf16)).filter(\.hasCode).map(\.range)
    }

    /// The statement under the cursor. A cursor right after a `;` belongs to the
    /// statement it terminates; one past the last statement picks the last one.
    public static func range(at cursor: Int, in text: String) -> Range<Int>? {
        let statements = segments(in: Array(text.utf16)).filter(\.hasCode)
        return (statements.first { cursor <= $0.end } ?? statements.last)?.range
    }

    public static func statements(in text: String) -> [String] {
        let utf16 = text.utf16
        return ranges(in: text).map { range in
            let start = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
            let end = utf16.index(utf16.startIndex, offsetBy: range.upperBound)
            return String(text[start..<end])
        }
    }

    // MARK: - Scanner

    private static let semicolon = UInt16(UInt8(ascii: ";"))
    private static let singleQuote = UInt16(UInt8(ascii: "'"))
    private static let doubleQuote = UInt16(UInt8(ascii: "\""))
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let dash = UInt16(UInt8(ascii: "-"))
    private static let hash = UInt16(UInt8(ascii: "#"))
    private static let slash = UInt16(UInt8(ascii: "/"))
    private static let star = UInt16(UInt8(ascii: "*"))
    private static let newline = UInt16(UInt8(ascii: "\n"))

    static func segments(in chars: [UInt16]) -> [Segment] {
        var segments: [Segment] = []
        var start = 0
        var hasCode = false
        var i = 0

        func close(at delimiter: Int, end: Int) {
            segments.append(Segment(range: trimmed(start..<delimiter, in: chars), end: end, hasCode: hasCode))
            start = end
            hasCode = false
        }

        while i < chars.count {
            let c = chars[i]
            if c == singleQuote || c == doubleQuote || c == backtick {
                hasCode = true
                i = endOfQuoted(chars, from: i)
            } else if c == dash, at(chars, i + 1) == dash, isWhitespaceOrEnd(at(chars, i + 2)) {
                i = endOfLine(chars, from: i)
            } else if c == hash {
                i = endOfLine(chars, from: i)
            } else if c == slash, at(chars, i + 1) == star {
                i = endOfBlockComment(chars, from: i)
            } else if c == semicolon {
                close(at: i, end: i + 1)
                i += 1
            } else {
                if !isWhitespace(c) { hasCode = true }
                i += 1
            }
        }
        if start < chars.count {
            close(at: chars.count, end: chars.count)
        }
        return segments
    }

    /// Index just past the closing quote, or the end of text if unterminated.
    /// Doubled quotes (`''`) fall out naturally as close + reopen.
    private static func endOfQuoted(_ chars: [UInt16], from open: Int) -> Int {
        let quote = chars[open]
        var i = open + 1
        while i < chars.count {
            if chars[i] == backslash, quote != backtick {
                i += 2
            } else if chars[i] == quote {
                return i + 1
            } else {
                i += 1
            }
        }
        return chars.count
    }

    private static func endOfLine(_ chars: [UInt16], from i: Int) -> Int {
        var i = i
        while i < chars.count, chars[i] != newline { i += 1 }
        return i
    }

    private static func endOfBlockComment(_ chars: [UInt16], from i: Int) -> Int {
        var i = i + 2
        while i < chars.count {
            if chars[i] == star, at(chars, i + 1) == slash { return i + 2 }
            i += 1
        }
        return chars.count
    }

    private static func trimmed(_ range: Range<Int>, in chars: [UInt16]) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, isWhitespace(chars[lower]) { lower += 1 }
        while upper > lower, isWhitespace(chars[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    private static func at(_ chars: [UInt16], _ i: Int) -> UInt16? {
        i < chars.count ? chars[i] : nil
    }

    private static func isWhitespace(_ c: UInt16) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C
    }

    private static func isWhitespaceOrEnd(_ c: UInt16?) -> Bool {
        c.map(isWhitespace) ?? true
    }
}
