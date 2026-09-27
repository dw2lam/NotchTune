import Foundation

/// Flattens an agent's Markdown reply into a single-paragraph plain-text
/// preview for the completion toast. Not a Markdown parser — it strips the
/// syntax that would otherwise show up as noise in a three-line excerpt.
enum CompletionPreviewText {
    nonisolated static func plain(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")

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
}
