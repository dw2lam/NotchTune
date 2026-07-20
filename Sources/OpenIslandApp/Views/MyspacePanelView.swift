import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MyspaceContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MyspaceListContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MyspaceAutoHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content()
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MyspaceListContentHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(contentHeight > maxHeight ? .automatic : .hidden)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
        .onPreferenceChange(MyspaceListContentHeightKey.self) { height in
            if height > 0 {
                contentHeight = height
            }
        }
    }
}

struct MyspacePanelView: View {
    enum Section: String, CaseIterable, Identifiable {
        case space = "Space"
        case reminders = "Reminders"

        var id: String { rawValue }
    }

    let store: MyspaceStore
    let onFilesHeld: () -> Void
    @State private var selectedSection: Section = .space
    @State private var draft = ""
    @State private var pendingAttachments: [URL] = []
    @State private var reminderEnabled = false
    @State private var reminderAt = Date.now.addingTimeInterval(60 * 60)
    @State private var isDropTargeted = false
    @State private var composerMessage: String?
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            sectionPicker

            if selectedSection == .space {
                composer
                thoughtList(store.thoughts)
            } else {
                reminderList
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MyspaceContentHeightKey.self,
                    value: geometry.size.height
                )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            holdFiles(urls)
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isDropTargeted = targeted
            }
        }
        .transition(.opacity)
    }

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(Section.allCases) { section in
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section == .space ? "square.grid.2x2" : "bell")
                            .font(.system(size: 9, weight: .semibold))
                        Text(section.rawValue)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(selectedSection == section ? .white : .white.opacity(0.42))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        selectedSection == section ? .white.opacity(0.12) : .clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .focused($composerFocused)
                .frame(minHeight: 44, maxHeight: 62)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Drop a thought here…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.28))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(pendingAttachments, id: \.self) { url in
                            pendingAttachmentChip(url)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if reminderEnabled {
                DatePicker(
                    "Remind me",
                    selection: $reminderAt,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .colorScheme(.dark)
                .font(.system(size: 10))
            }

            HStack(spacing: 7) {
                composerButton(
                    systemName: "waveform",
                    help: "Focus this field, then use Whisper, Superwhisper, or macOS Dictation."
                ) {
                    composerFocused = true
                    composerMessage = "Listening for your dictation app…"
                }

                composerButton(systemName: "paperclip", help: "Attach files") {
                    chooseAttachments()
                }

                composerButton(
                    systemName: reminderEnabled ? "bell.fill" : "bell",
                    help: "Add a reminder",
                    isActive: reminderEnabled
                ) {
                    withAnimation(.smooth(duration: 0.2)) {
                        reminderEnabled.toggle()
                    }
                }

                if let message = composerMessage ?? store.lastErrorMessage {
                    Text(message)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button(action: saveThought) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty ? 0.35 : 1)
                .accessibilityLabel("Save thought")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isDropTargeted ? 0.12 : 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isDropTargeted ? Color.accentColor.opacity(0.8) : .white.opacity(0.08),
                            lineWidth: isDropTargeted ? 1.5 : 0.5
                        )
                )
        )
    }

    private func composerButton(
        systemName: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : .white.opacity(0.55))
                .frame(width: 23, height: 23)
                .background(.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func pendingAttachmentChip(_ url: URL) -> some View {
        HStack(spacing: 5) {
            Image(systemName: attachmentIcon(for: url))
                .font(.system(size: 9))
            Text(url.lastPathComponent)
                .font(.system(size: 9.5))
                .lineLimit(1)
            Button {
                pendingAttachments.removeAll { $0 == url }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white.opacity(0.07), in: Capsule())
    }

    @ViewBuilder
    private func thoughtList(_ thoughts: [MyspaceThought]) -> some View {
        if thoughts.isEmpty {
            emptyState(
                icon: "tray",
                title: "Your space is quiet",
                detail: "Save a thought, dictate an idea, or drop in a file."
            )
        } else {
            MyspaceAutoHeightScrollView(maxHeight: 210) {
                VStack(spacing: 7) {
                    ForEach(thoughts) { thought in
                        thoughtRow(thought, showsCompletionControl: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var reminderList: some View {
        if store.activeReminders.isEmpty {
            emptyState(
                icon: "bell.slash",
                title: "No active reminders",
                detail: "Add a reminder to any thought and it will stay here."
            )
        } else {
            MyspaceAutoHeightScrollView(maxHeight: 210) {
                VStack(spacing: 7) {
                    ForEach(store.activeReminders) { thought in
                        thoughtRow(thought, showsCompletionControl: true)
                    }
                }
            }
        }
    }

    private func thoughtRow(_ thought: MyspaceThought, showsCompletionControl: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if showsCompletionControl {
                Button {
                    store.toggleReminderCompleted(id: thought.id)
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete reminder")
            }

            VStack(alignment: .leading, spacing: 6) {
                if !thought.text.isEmpty {
                    Text(thought.text)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !thought.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(thought.attachments.prefix(3)) { attachment in
                            Button {
                                NSWorkspace.shared.open(
                                    store.attachmentURL(for: attachment, thoughtID: thought.id)
                                )
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: attachmentIcon(forFilename: attachment.originalFilename))
                                    Text(attachment.originalFilename)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Text(thought.createdAt, style: .relative)
                    if let reminderAt = thought.reminderAt {
                        Label {
                            Text(reminderAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        } icon: {
                            Image(systemName: "bell.fill")
                        }
                    }
                }
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.3))
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    store.deleteThought(id: thought.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete thought")
        }
        .padding(9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 12)
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.24))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 94)
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]
        if panel.runModal() == .OK {
            appendPendingAttachments(panel.urls)
        }
    }

    private func appendPendingAttachments(_ urls: [URL]) {
        let existing = Set(pendingAttachments)
        pendingAttachments.append(contentsOf: urls.filter { !existing.contains($0) })
        composerMessage = "\(pendingAttachments.count) attachment\(pendingAttachments.count == 1 ? "" : "s") ready"
    }

    private func holdFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        do {
            try store.holdFiles(urls)
            composerMessage = "Held \(urls.count) file\(urls.count == 1 ? "" : "s")"
            onFilesHeld()
            return true
        } catch {
            composerMessage = error.localizedDescription
            return false
        }
    }

    private func saveThought() {
        do {
            try store.addThought(
                text: draft,
                attachmentURLs: pendingAttachments,
                reminderAt: reminderEnabled ? reminderAt : nil
            )
            draft = ""
            pendingAttachments = []
            reminderEnabled = false
            reminderAt = .now.addingTimeInterval(60 * 60)
            composerMessage = "Saved"
            composerFocused = false
        } catch {
            composerMessage = error.localizedDescription
        }
    }

    private func attachmentIcon(for url: URL) -> String {
        attachmentIcon(forFilename: url.lastPathComponent)
    }

    private func attachmentIcon(forFilename filename: String) -> String {
        guard let type = UTType(filenameExtension: (filename as NSString).pathExtension) else {
            return "doc"
        }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        return "doc"
    }
}
