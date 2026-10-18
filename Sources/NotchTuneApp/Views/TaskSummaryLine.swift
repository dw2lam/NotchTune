import NotchTuneCore
import SwiftUI

/// A finished turn's `TaskSummary` as short, iconed parts: "Edited 4 files",
/// "Tests passed", "3m 12s". Pure, so the wording is unit-testable.
struct TaskSummaryParts: Equatable {
    enum Tone: Equatable {
        case plain
        case positive
        case negative
    }

    struct Part: Equatable, Identifiable {
        let symbol: String
        let text: String
        var tone: Tone = .plain
        /// Hover text: the edited files' names.
        var help: String?

        var id: String { symbol }
    }

    let parts: [Part]

    /// Nil when the turn did nothing worth a line (it only talked).
    init?(summary: TaskSummary?, lang: LanguageManager = .shared) {
        guard let summary, !summary.isEmpty else { return nil }
        var parts: [Part] = []

        if summary.fileCount == 1, let name = summary.fileNames.first {
            parts.append(Part(symbol: "pencil", text: lang.t("task.summary.editedFile", name)))
        } else if summary.fileCount > 1 {
            let names = summary.fileNames.joined(separator: ", ")
            let more = summary.fileCount - summary.fileNames.count
            parts.append(Part(
                symbol: "pencil",
                text: lang.t("task.summary.editedFiles", summary.fileCount),
                help: more > 0 ? lang.t("task.summary.filesAndMore", names, more) : names
            ))
        }

        switch summary.tests {
        case .passed?:
            parts.append(Part(symbol: "checkmark.circle.fill", text: lang.t("task.summary.testsPassed"), tone: .positive))
        case .failed?:
            parts.append(Part(symbol: "xmark.circle.fill", text: lang.t("task.summary.testsFailed"), tone: .negative))
        case .ran?:
            parts.append(Part(symbol: "testtube.2", text: lang.t("task.summary.testsRan")))
        case nil:
            break
        }

        // Commands only when nothing more telling happened.
        if parts.isEmpty, summary.commandCount > 0 {
            let text = summary.commandCount == 1
                ? lang.t("task.summary.command")
                : lang.t("task.summary.commands", summary.commandCount)
            parts.append(Part(symbol: "terminal", text: text))
        }

        if let duration = summary.duration, let text = Self.durationText(duration) {
            parts.append(Part(symbol: "clock", text: text))
        }

        self.parts = parts
    }

    /// One line of plain text, for VoiceOver and the closed pill's peek.
    var compactText: String {
        parts.map(\.text).joined(separator: " · ")
    }

    /// "42s", "3m 12s", "3m", "1h 5m"; nil under a second.
    static func durationText(_ duration: TimeInterval) -> String? {
        let seconds = Int(duration.rounded())
        guard seconds >= 1 else { return nil }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            let s = seconds % 60
            return s == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(s)s"
        }
        let m = (seconds % 3600) / 60
        return m == 0 ? "\(seconds / 3600)h" : "\(seconds / 3600)h \(m)m"
    }
}

/// The summary drawn as a row of small icon + text parts in the island's
/// type; only the test result's icon carries colour.
struct TaskSummaryLine: View {
    let parts: TaskSummaryParts
    var fontSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(parts.parts.enumerated()), id: \.element.id) { index, part in
                HStack(spacing: 4) {
                    Image(systemName: part.symbol)
                        .font(.system(size: fontSize - 1.5, weight: .semibold))
                        .foregroundStyle(iconColor(part.tone))
                    Text(part.text)
                        .font(.system(size: fontSize, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(V6Palette.paper.opacity(0.62))
                        .truncationMode(.middle)
                }
                .lineLimit(1)
                // A long file name gives way first; the result and time stay whole.
                .layoutPriority(index == 0 && parts.parts.count > 1 ? 0 : 1)
                .help(part.help ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.compactText)
    }

    private func iconColor(_ tone: TaskSummaryParts.Tone) -> Color {
        switch tone {
        case .plain: V6Palette.paper.opacity(0.48)
        case .positive: IslandDesignPalette.Status.completed
        case .negative: IslandDesignPalette.Status.waitingForApproval
        }
    }
}
