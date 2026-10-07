import AppKit
import SwiftUI

/// Gives the model on-demand access to the editor's selection without pushing
/// every caret move through SwiftUI state.
@MainActor
final class SQLEditorController {
    fileprivate weak var textView: NSTextView?

    var selectedRange: NSRange {
        textView?.selectedRange() ?? NSRange(location: 0, length: 0)
    }

    /// Briefly highlights the range about to run, like TablePlus does.
    func flash(_ range: NSRange) {
        guard let textView, NSMaxRange(range) <= (textView.string as NSString).length else { return }
        textView.showFindIndicator(for: range)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

struct SQLTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: SQLEditorController

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        textView.font = font
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)

        textView.string = text
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.highlighter
        if let storage = textView.textStorage {
            SQLHighlighter.highlight(storage)
        }
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let highlighter = SQLHighlighter()

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Single-pass regex highlighter; one alternation so strings and comments win
/// over keywords inside them.
final class SQLHighlighter: NSObject, NSTextStorageDelegate {
    private static let keywords = """
        SELECT FROM WHERE AND OR NOT NULL IS IN LIKE BETWEEN EXISTS JOIN INNER LEFT RIGHT OUTER CROSS \
        ON USING AS GROUP BY ORDER HAVING LIMIT OFFSET UNION ALL DISTINCT INSERT INTO VALUES UPDATE SET \
        DELETE CREATE ALTER DROP TABLE VIEW INDEX DATABASE SCHEMA PRIMARY KEY FOREIGN REFERENCES UNIQUE \
        DEFAULT AUTO_INCREMENT CONSTRAINT IF CASE WHEN THEN ELSE END ASC DESC SHOW DESCRIBE EXPLAIN USE \
        BEGIN COMMIT ROLLBACK START TRANSACTION WITH RECURSIVE TRUNCATE REPLACE TRUE FALSE INTERVAL CALL \
        PROCEDURE FUNCTION TRIGGER RETURNS DECLARE GRANT REVOKE ADD COLUMN MODIFY CHANGE RENAME TO \
        DUPLICATE IGNORE FOR LOCK OVER PARTITION WINDOW COUNT SUM AVG MIN MAX
        """.split(separator: " ").joined(separator: "|")

    private static let regex = try! NSRegularExpression(
        pattern: [
            #"(--[ \t][^\n]*|--$|#[^\n]*|/\*[\s\S]*?(?:\*/|$))"#,  // 1 comments
            #"('(?:\\.|''|[^'\\])*'?|"(?:\\.|""|[^"\\])*"?)"#,    // 2 strings
            #"(`[^`]*`?)"#,                                          // 3 identifiers
            #"\b(\d+(?:\.\d+)?)\b"#,                                 // 4 numbers
            #"\b(\#(keywords))\b"#,                                  // 5 keywords
        ].joined(separator: "|"),
        options: [.caseInsensitive, .anchorsMatchLines]
    )

    private static let colors: [(group: Int, color: NSColor)] = [
        (1, .secondaryLabelColor),
        (2, .systemRed),
        (3, .systemTeal),
        (4, .systemBlue),
        (5, .systemPink),
    ]

    /// Beyond this, highlighting on every keystroke stops being free.
    private static let maxLength = 200_000

    static func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length <= maxLength else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
        regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let match else { return }
            for (group, color) in colors where match.range(at: group).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: color, range: match.range(at: group))
                break
            }
        }
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        Self.highlight(textStorage)
    }
}
