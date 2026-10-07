import Foundation

/// Flattens an agent's Markdown reply into a single-paragraph plain-text
/// preview for the completion toast. Not a Markdown parser — it strips the
/// syntax that would otherwise show up as noise in a three-line excerpt.
enum CompletionPreviewText {
    /// Longest stretch of the source that gets flattened. Every preview shows
    /// a line or three, yet this runs from view bodies (the finished
    /// live-activity subtitle is resolved many times per render) and each
    /// regex pass below is linear in the input, so a long reply must not
    /// cost more than its visible head.
    nonisolated static let maxSourceLength = 2_000

    nonisolated static func plain(_ markdown: String) -> String {
        var text = head(of: markdown).replacingOccurrences(of: "\r\n", with: "\n")

        // Fenced code: drop the fence lines, keep the code itself.
        text = text.replacingOccurrences(
            of: #"(?m)^[ \t]*(```|~~~)[^\n]*$"#,
            with: "",
            options: .regularExpression
        )
        // Images → alt text, links → link text.
        text = text.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // HTML tags.
        text = text.replacingOccurrences(
            of: #"</?[A-Za-z][^>]*>"#,
            with: "",
            options: .regularExpression
        )
        // Headings, block quotes, list markers, horizontal rules at line start.
        text = text.replacingOccurrences(
            of: #"(?m)^[ \t]*(#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+|\d+[.)][ \t]+)"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?m)^[ \t]*([-*_][ \t]*){3,}$"#,
            with: "",
            options: .regularExpression
        )
        // Table separator rows (|---|---|).
        text = text.replacingOccurrences(
            of: #"(?m)^[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(\|[ \t]*:?-{2,}:?[ \t]*)*\|?[ \t]*$"#,
            with: "",
            options: .regularExpression
        )
        // Emphasis + inline code markers.
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "~~", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(
            of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#,
            with: "$1",
            options: .regularExpression
        )
        // Table cell pipes read as separators.
        text = text.replacingOccurrences(of: " | ", with: " · ")
        text = text.replacingOccurrences(
            of: #"(?m)^[ \t]*\|[ \t]*|[ \t]*\|[ \t]*$"#,
            with: "",
            options: .regularExpression
        )
        // Collapse all whitespace (including newlines) into single spaces.
        text = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first `maxSourceLength` characters, cut back to the last line break
    /// in the second half of that window so no Markdown line (link, code span,
    /// table row) is split.
    nonisolated private static func head(of markdown: String) -> String {
        guard let limit = markdown.index(
            markdown.startIndex,
            offsetBy: maxSourceLength,
            limitedBy: markdown.endIndex
        ), limit < markdown.endIndex else {
            return markdown
        }
        let window = markdown[..<limit]
        if let lineBreak = window.lastIndex(where: \.isNewline),
           window.distance(from: window.startIndex, to: lineBreak) >= maxSourceLength / 2 {
            return String(window[..<lineBreak])
        }
        return String(window)
    }
}
