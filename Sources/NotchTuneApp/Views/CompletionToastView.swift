import NotchTuneCore
import SwiftUI

/// Position of the current toast inside the ring of recent completions.
struct CompletionToastQueuePosition: Equatable {
    let index: Int
    let count: Int
}

/// The compact "agent finished" surface that hangs off the notch.
///
/// Budgeted to roughly a fifth of the screen (see `NotificationSurfaceMetrics`):
/// one header line, the prompt that started the turn, a three-line plain-text
/// excerpt of the reply, and a single row of actions. Anything longer lives
/// behind "Jump" or the full session list — never inline.
struct CompletionToastView: View {
    let session: AgentSession
    let referenceDate: Date
    var queuePosition: CompletionToastQueuePosition?
    var totalSessionCount: Int
    var isFlashing = false
    var isInteractive = true
    var lang: LanguageManager = .shared
    let onJump: () -> Void
    var onReply: ((String) -> Void)?
    var onRotate: ((Bool) -> Void)?
    let onShowAll: () -> Void

    @State private var isReplying = false
    @State private var replyText = ""

    private static let horizontalInset: CGFloat = 16
    private static let topInset: CGFloat = 8
    private static let bottomInset: CGFloat = 12
    private static let rowSpacing: CGFloat = 6
    private static let actionRowHeight: CGFloat = 28
    private static let previewFont = Font.system(size: 12.5, weight: .regular)

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            header

            if let promptLine {
                Text(promptLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(V6Palette.paper.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !previewText.isEmpty {
                Text(previewText)
                    .font(Self.previewFont)
                    .foregroundStyle(V6Palette.paper.opacity(0.88))
                    .lineSpacing(1.5)
                    .lineLimit(NotificationSurfaceMetrics.previewLineLimit)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            actionRow
                .padding(.top, 2)
        }
        .padding(.horizontal, Self.horizontalInset)
        .padding(.top, Self.topInset)
        .padding(.bottom, Self.bottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive, !isReplying else { return }
            onJump()
        }
        .overlay {
            if isFlashing {
                (Color(hex: session.tool.brandColorHex) ?? .blue)
                    .opacity(0.18)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headlineText)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                Circle()
                    .fill(IslandDesignPalette.Status.completed)
                    .frame(width: 7, height: 7)
                    .shadow(color: IslandDesignPalette.Status.completed.opacity(0.7), radius: 3)

                Text(headlineText)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(V6Palette.paper.opacity(0.94))
                    .lineLimit(1)
            }

            Text(workspaceText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(V6Palette.paper.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let terminal = session.spotlightTerminalBadge, !terminal.isEmpty {
                    Text(terminal)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.42))
                        .lineLimit(1)
                }
                Text(session.spotlightAgeBadge)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.42))
            }
        }
        .frame(height: 18)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRow: some View {
        if isReplying {
            replyRow
        } else {
            HStack(spacing: 8) {
                Button(action: onJump) {
                    NotificationKeyHintedTitle(keys: "⏎") {
                        Label(jumpTitle, systemImage: "arrow.up.forward")
                            .labelStyle(.titleAndIcon)
                    }
                    // ⌘R from NotificationCardKeyCommand: open the reply row.
                    // Lives on the Jump label because the action row (and so
                    // this label) is exactly what the reply row replaces.
                    .onReceive(NotificationCenter.default.publisher(for: .notificationCardKeyCommand)) { notification in
                        guard onReply != nil,
                              NotificationCardKeyCommandBus.command(from: notification, sessionID: session.id) == .openReply else {
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isReplying = true
                        }
                    }
                }
                .buttonStyle(ToastButtonStyle(kind: .primary))

                if onReply != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isReplying = true
                        }
                    } label: {
                        Label(lang.t("completion.toast.reply"), systemImage: "arrowshape.turn.up.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(ToastButtonStyle(kind: .secondary))
                }

                Spacer(minLength: 4)

                if let queuePosition, queuePosition.count > 1 {
                    queueControls(queuePosition)
                }

                Button(action: onShowAll) {
                    Text(lang.t("completion.toast.showAll", totalSessionCount))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(V6Palette.paper.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
            .frame(height: Self.actionRowHeight)
            .transition(.opacity)
        }
    }

    private func queueControls(_ position: CompletionToastQueuePosition) -> some View {
        HStack(spacing: 2) {
            Button {
                onRotate?(false)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(ToastIconButtonStyle())
            .accessibilityLabel(lang.t("completion.toast.previous"))

            Text("\(position.index + 1)/\(position.count)")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(V6Palette.paper.opacity(0.5))
                .monospacedDigit()

            Button {
                onRotate?(true)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(ToastIconButtonStyle())
            .accessibilityLabel(lang.t("completion.toast.next"))
        }
        .padding(.trailing, 4)
    }

    private var replyRow: some View {
        HStack(spacing: 8) {
            ReplyTextField(
                placeholder: lang.t("completion.replyPlaceholder", session.completionReplyRecipientName),
                text: $replyText,
                onSubmit: { submitReply() }
            )
            .frame(height: Self.actionRowHeight)

            Button {
                submitReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        trimmedReply.isEmpty ? V6Palette.paper.opacity(0.22) : V6Palette.paper.opacity(0.92)
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedReply.isEmpty)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isReplying = false
                    replyText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(ToastIconButtonStyle())
            .accessibilityLabel(lang.t("settings.general.cancel"))
        }
        .frame(height: Self.actionRowHeight)
        .transition(.opacity)
    }

    private var trimmedReply: String {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitReply() {
        let text = trimmedReply
        guard !text.isEmpty else { return }
        replyText = ""
        isReplying = false
        onReply?(text)
    }

    // MARK: - Text

    private var headlineText: String {
        lang.t("completion.toast.finished", session.tool.displayName)
    }

    private var workspaceText: String {
        let workspace = session.spotlightWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = workspace.isEmpty ? session.tool.displayName : workspace
        guard let branch = session.spotlightWorktreeBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty else {
            return title
        }
        return "\(title) (\(branch))"
    }

    private var promptLine: String? {
        let prompt = session.latestUserPromptText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? session.initialUserPromptText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prompt, !prompt.isEmpty else { return nil }
        return "You: \(prompt)"
    }

    private var previewText: String {
        Self.previewText(for: session)
    }

    private var jumpTitle: String {
        if let terminal = session.spotlightTerminalBadge, !terminal.isEmpty {
            return lang.t("completion.toast.jumpTo", terminal)
        }
        return lang.t("completion.toast.jump")
    }

    static func previewText(for session: AgentSession) -> String {
        if let text = session.completionAssistantMessageText, !text.isEmpty {
            let plain = CompletionPreviewText.plain(text)
            if !plain.isEmpty { return plain }
        }
        let summary = CompletionPreviewText.plain(session.summary)
        return summary == SessionPhase.completed.displayName ? "" : summary
    }

    // MARK: - Height estimate (window sizing before the first SwiftUI measure)

    /// Estimates the toast height so the panel opens at (nearly) its final
    /// size instead of flashing a tall blank surface and shrinking.
    nonisolated static func estimatedHeight(
        for session: AgentSession,
        contentWidth: CGFloat,
        hasPrompt: Bool
    ) -> CGFloat {
        var height = topInset + 18 + rowSpacing
        if hasPrompt {
            height += 14 + rowSpacing
        }
        let preview = previewText(for: session)
        if !preview.isEmpty {
            let font = NSFont.systemFont(ofSize: 12.5)
            let lineHeight = ceil(font.ascender - font.descender + font.leading) + 1.5
            let available = max(120, contentWidth - horizontalInset * 2)
            let rect = (preview as NSString).boundingRect(
                with: NSSize(width: available, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            let lines = min(
                CGFloat(NotificationSurfaceMetrics.previewLineLimit),
                max(1, ceil(rect.height / lineHeight))
            )
            height += lines * lineHeight + rowSpacing
        }
        height += 2 + actionRowHeight + bottomInset
        return ceil(height)
    }
}

// MARK: - Button styles

private struct ToastButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(background.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: V6Palette.ink.opacity(0.92)
        case .secondary: V6Palette.paper.opacity(0.82)
        }
    }

    private var background: Color {
        switch kind {
        case .primary: V6Palette.paper.opacity(0.9)
        case .secondary: .white.opacity(0.08)
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary: .clear
        case .secondary: .white.opacity(0.1)
        }
    }
}

private struct ToastIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(V6Palette.paper.opacity(configuration.isPressed ? 0.9 : 0.55))
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.06), in: Circle())
            .contentShape(Circle())
    }
}
