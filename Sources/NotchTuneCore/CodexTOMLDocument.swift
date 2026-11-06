import Foundation

/// Just enough TOML to find where a key lives in `~/.codex/config.toml`
/// without a parser dependency. It reads the file line by line, keeps every
/// byte of what it doesn't change, and knows which lines are really table
/// headers: a `[` inside a multi-line array or string isn't one.
struct CodexTOMLDocument {
    enum Line: Equatable {
        case header(path: [String], isArrayTable: Bool)
        case assignment(key: [String], value: String)
        /// Blank lines, comments and the continuation of a multi-line value.
        case other
    }

    private(set) var rawLines: [String]
    let lineEnding: String

    init(_ contents: String) {
        lineEnding = contents.contains("\r\n") ? "\r\n" : "\n"
        rawLines = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
    }

    var text: String {
        rawLines.joined(separator: lineEnding)
    }

    mutating func replaceLine(at index: Int, with line: String) {
        rawLines[index] = line
    }

    mutating func insertLine(_ line: String, at index: Int) {
        rawLines.insert(line, at: index)
    }

    mutating func removeLine(at index: Int) {
        rawLines.remove(at: index)
    }

    /// One entry per raw line.
    var lines: [Line] {
        var scanner = Scanner()
        return rawLines.map { scanner.classify($0) }
    }

    /// Indices of every `[path]` header. More than one means the file is
    /// already invalid TOML.
    func headerIndices(of path: [String]) -> [Int] {
        lines.enumerated().compactMap { index, line in
            if case .header(path, false) = line {
                return index
            }
            return nil
        }
    }

    /// The lines inside `[path]`: after its header, up to the next header of
    /// any kind.
    func tableBody(of path: [String]) -> Range<Int>? {
        guard let header = headerIndices(of: path).first else {
            return nil
        }

        let classified = lines
        var end = classified.count
        for index in (header + 1)..<classified.count {
            if case .header = classified[index] {
                end = index
                break
            }
        }

        return (header + 1)..<end
    }

    /// Everything before the first table header, where `features.hooks = true`
    /// and `features = { ... }` live.
    var rootBody: Range<Int> {
        let classified = lines
        let end = classified.firstIndex { line in
            if case .header = line {
                return true
            }
            return false
        } ?? classified.count
        return 0..<end
    }

    /// Whether the table is defined by a header, a dotted key, or inline.
    /// Those forms can't be mixed, so an edit has to use the one already there.
    func indexOfRootAssignment(key: [String]) -> Int? {
        let classified = lines
        return rootBody.first { index in
            if case .assignment(key, _) = classified[index] {
                return true
            }
            return false
        }
    }

    func rootAssignments(prefix: String) -> [Int] {
        let classified = lines
        return rootBody.filter { index in
            if case let .assignment(key, _) = classified[index] {
                return key.count > 1 && key[0] == prefix
            }
            return false
        }
    }

    private struct Scanner {
        private var openString: String?
        private var depth = 0

        mutating func classify(_ raw: String) -> Line {
            if openString != nil || depth > 0 {
                _ = scan(raw[...])
                return .other
            }

            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                return .other
            }

            if line.hasPrefix("[") {
                return Self.header(in: line) ?? .other
            }

            guard let equals = Self.topLevelEquals(in: line),
                  let key = Self.keyPath(String(line[..<equals])) else {
                return .other
            }

            let rest = line[line.index(after: equals)...]
            let end = scan(rest)
            return .assignment(
                key: key,
                value: String(rest[..<end]).trimmingCharacters(in: .whitespaces)
            )
        }

        /// Follows strings and brackets through a value so a multi-line one
        /// carries over to the next line. Returns where a comment starts.
        private mutating func scan(_ text: Substring) -> Substring.Index {
            var index = text.startIndex

            while index < text.endIndex {
                if let quote = openString {
                    if text[index...].hasPrefix(quote) {
                        index = text.index(index, offsetBy: quote.count)
                        openString = nil
                        continue
                    }

                    if text[index] == "\\", quote.first == "\"" {
                        index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                        continue
                    }

                    index = text.index(after: index)
                    continue
                }

                let rest = text[index...]
                if rest.hasPrefix("\"\"\"") || rest.hasPrefix("'''") {
                    openString = String(rest.prefix(3))
                    index = text.index(index, offsetBy: 3)
                    continue
                }

                switch text[index] {
                case "\"", "'":
                    openString = String(text[index])
                case "[", "{":
                    depth += 1
                case "]", "}":
                    depth = max(0, depth - 1)
                case "#":
                    return index
                default:
                    break
                }

                index = text.index(after: index)
            }

            // Only triple quotes span lines; an unclosed single quote is the
            // user's typo and shouldn't swallow the rest of the file.
            if let quote = openString, quote.count == 1 {
                openString = nil
            }

            return text.endIndex
        }

        private static func header(in line: String) -> Line? {
            let isArrayTable = line.hasPrefix("[[")
            let open = isArrayTable ? 2 : 1
            let close = isArrayTable ? "]]" : "]"
            let body = line.dropFirst(open)

            var quote: Character?
            var index = body.startIndex
            while index < body.endIndex {
                let character = body[index]
                if let current = quote {
                    if character == current {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if body[index...].hasPrefix(close) {
                    let trailing = body[body.index(index, offsetBy: close.count)...]
                        .trimmingCharacters(in: .whitespaces)
                    guard trailing.isEmpty || trailing.hasPrefix("#"),
                          let path = keyPath(String(body[..<index])) else {
                        return nil
                    }
                    return .header(path: path, isArrayTable: isArrayTable)
                }
                index = body.index(after: index)
            }

            return nil
        }

        private static func topLevelEquals(in line: String) -> String.Index? {
            var quote: Character?
            for index in line.indices {
                let character = line[index]
                if let current = quote {
                    if character == current {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "=" {
                    return index
                }
            }
            return nil
        }

        /// `a."b.c".d` as `["a", "b.c", "d"]`.
        static func keyPath(_ raw: String) -> [String]? {
            var parts: [String] = []
            var current = ""
            var quote: Character?

            for character in raw {
                if let open = quote {
                    if character == open {
                        quote = nil
                    } else {
                        current.append(character)
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "." {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else {
                    current.append(character)
                }
            }

            parts.append(current.trimmingCharacters(in: .whitespaces))
            return parts.contains(where: \.isEmpty) ? nil : parts
        }
    }
}
