import AppKit
@preconcurrency import QuickLookThumbnailing
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

private struct MyspaceAttachmentPreview: View {
    let url: URL
    let filename: String
    @State private var thumbnail: NSImage?

    private var fallbackIcon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    private var fileExtension: String {
        let value = url.pathExtension.uppercased()
        return value.isEmpty ? "FILE" : String(value.prefix(5))
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: thumbnail ?? fallbackIcon)
                    .resizable()
                    .aspectRatio(contentMode: thumbnail == nil ? .fit : .fill)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(thumbnail == nil ? 4 : 0)

                Text(fileExtension)
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                    .offset(x: 3, y: 3)
            }
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

            Text(filename)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 78, alignment: .leading)
        }
        .frame(width: 138, alignment: .leading)
        .task(id: url) {
            thumbnail = await quickLookThumbnail()
        }
    }

    private func quickLookThumbnail() async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: scale,
            representationTypes: [.thumbnail, .lowQualityThumbnail, .icon]
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
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
                dropShelf
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

    private var dropShelf: some View {
        Button {
            chooseHeldFiles()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .white.opacity(0.65))
                    .symbolEffect(.bounce, value: isDropTargeted)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isDropTargeted ? "Drop to hold it" : "Throw anything in")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Drag a file near the notch. Myspace opens and keeps a local copy.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : .white.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isDropTargeted ? Color.accentColor.opacity(0.85) : .white.opacity(0.16),
                        style: StrokeStyle(
                            lineWidth: isDropTargeted ? 1.5 : 1,
                            dash: isDropTargeted ? [] : [5, 4]
                        )
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hold files in Myspace")
        .help("Choose files, or drag them near the notch to hold a local copy.")
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
                LazyVStack(spacing: 11, pinnedViews: [.sectionHeaders]) {
                    ForEach(MyspaceStore.groupThoughtsByDay(thoughts)) { group in
                        SwiftUI.Section {
                            VStack(spacing: 7) {
                                ForEach(group.thoughts) { thought in
                                    thoughtRow(thought, showsCompletionControl: false)
                                }
                            }
                        } header: {
                            dayHeader(group.day)
                        }
                    }
                }
            }
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        HStack(spacing: 7) {
            Text(dayTitle(date))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.46))

            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(height: 0.5)
        }
        .padding(.vertical, 2)
        .background(V6Palette.ink.opacity(0.92))
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .uppercased()
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
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(thought.attachments) { attachment in
                                let attachmentURL = store.attachmentURL(
                                    for: attachment,
                                    thoughtID: thought.id
                                )
                                Button {
                                    NSWorkspace.shared.open(attachmentURL)
                                } label: {
                                    MyspaceAttachmentPreview(
                                        url: attachmentURL,
                                        filename: attachment.originalFilename
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open \(attachment.originalFilename)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                HStack(spacing: 6) {
                    Label {
                        Text(thought.createdAt, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .accessibilityLabel(
                        "Added \(thought.createdAt.formatted(date: .omitted, time: .complete))"
                    )
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

    private func chooseHeldFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]
        if panel.runModal() == .OK {
            _ = holdFiles(panel.urls)
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
