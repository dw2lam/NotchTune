import SwiftUI

/// Pick something to play from the selected player: a section switcher
/// (Playlists / Songs, or Pinned / Recent for Spotify), search, Spotify link
/// pinning, and an "Open" button for the full app.
struct MusicLibraryChooserView: View {
    @Bindable var library: MusicLibraryBrowser
    let player: MusicPlayerKind

    @Environment(\.islandControlGlass) private var usesGlass
    @State private var isPinFieldOpen = false
    @State private var pinDraft = ""
    @FocusState private var focusedField: Field?

    private enum Field { case search, pin }

    static let headerHeight: CGFloat = 26
    static let rowHeight: CGFloat = 38
    static let rowSpacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .frame(height: Self.headerHeight)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { statusToast }
        }
        .animation(.easeInOut(duration: 0.18), value: library.isSearchActive)
        .animation(.easeInOut(duration: 0.18), value: isPinFieldOpen)
        .onChange(of: player) { _, _ in closePinField() }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if library.isSearchActive {
            searchHeader
                .transition(.opacity)
        } else if isPinFieldOpen {
            pinHeader
                .transition(.opacity)
        } else {
            HStack(spacing: 6) {
                sectionPicker
                Spacer(minLength: 4)
                iconButton("magnifyingglass", help: searchHelp) {
                    closePinField()
                    library.beginSearch()
                    focusedField = .search
                }
                if player == .spotify {
                    iconButton("plus", help: "Pin a Spotify link") {
                        openPinField()
                    }
                }
                openAppButton
            }
            .islandGlassContainer(enabled: usesGlass, spacing: 6)
            .transition(.opacity)
        }
    }

    private var searchHelp: String {
        player == .appleMusic ? "Search your library" : "Search pinned and recent"
    }

    private var sectionPicker: some View {
        HStack(spacing: 2) {
            ForEach(MusicLibraryBrowser.Section.allCases) { section in
                let isSelected = library.section == section
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { library.section = section }
                } label: {
                    Text(section.title(for: player))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.46))
                        .padding(.horizontal, 11)
                        .frame(height: Self.headerHeight - 6)
                        .background(isSelected ? Color.white.opacity(0.12) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white.opacity(0.04), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.07), lineWidth: 0.5) }
    }

    private var searchHeader: some View {
        HStack(spacing: 6) {
            fieldCapsule(systemImage: "magnifyingglass") {
                TextField(
                    player == .appleMusic ? "Search your library" : "Search pinned & recent",
                    text: Binding(
                        get: { library.query ?? "" },
                        set: { library.updateQuery($0) }
                    )
                )
                .focused($focusedField, equals: .search)
                .onExitCommand { library.endSearch() }
                if library.isSearchingLibrary {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            }
            iconButton("xmark", help: "Close search") {
                library.endSearch()
                focusedField = nil
            }
        }
        .islandGlassContainer(enabled: usesGlass, spacing: 6)
        .onAppear { focusedField = .search }
    }

    private var pinHeader: some View {
        HStack(spacing: 6) {
            fieldCapsule(systemImage: "link") {
                TextField("Paste a Spotify playlist, album or song link", text: $pinDraft)
                    .focused($focusedField, equals: .pin)
                    .onSubmit(submitPin)
                    .onExitCommand { closePinField() }
                    .onChange(of: pinDraft) { _, newValue in
                        // A pasted link pins straight away.
                        if SpotifyLink.parse(newValue) != nil { submitPin() }
                    }
            }
            Button(action: submitPin) {
                Text("Pin")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .frame(height: Self.headerHeight - 2)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(MusicPressButtonStyle())
            .disabled(pinDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(pinDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            iconButton("xmark", help: "Cancel") { closePinField() }
        }
        .islandGlassContainer(enabled: usesGlass, spacing: 6)
        .onAppear { focusedField = .pin }
    }

    private func fieldCapsule<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            content()
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.headerHeight)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5) }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: Self.headerHeight - 2, height: Self.headerHeight - 2)
        }
        .buttonStyle(IslandGlassIconButtonStyle(
            fallbackFill: .white.opacity(0.08),
            foreground: .white.opacity(0.72)
        ))
        .help(help)
        .accessibilityLabel(help)
    }

    /// "Open" with the player's own app icon.
    private var openAppButton: some View {
        Button(action: library.openPlayerApp) {
            HStack(spacing: 5) {
                if let icon = MusicPlayerIcon.icon(for: player) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 15, height: 15)
                }
                Text("Open")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(height: Self.headerHeight - 2)
            .modifier(MusicCapsuleChrome(usesGlass: usesGlass))
            .contentShape(Capsule())
        }
        .buttonStyle(MusicPressButtonStyle())
        .help("Open \(player.displayName)")
        .accessibilityLabel("Open \(player.displayName)")
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let items = library.visibleItems
        if !items.isEmpty {
            itemGrid(items)
        } else if library.isLoadingLibrary {
            MusicChooserMessage(
                title: "Reading your library…",
                detail: nil
            ) {
                ProgressView().controlSize(.small).tint(.white)
            }
        } else if library.isSearchActive, !library.trimmedQuery.isEmpty {
            if library.isSearchingLibrary {
                MusicChooserMessage(title: "Searching…", detail: nil) {
                    ProgressView().controlSize(.small).tint(.white)
                }
            } else {
                MusicChooserMessage(
                    title: "No matches",
                    detail: noMatchesDetail
                )
            }
        } else {
            emptyMessage
        }
    }

    private var noMatchesDetail: String {
        if player == .appleMusic, !library.isPlayerRunning {
            return "Searching saved playlists and songs. Open Apple Music to search everything."
        }
        return "Nothing matches \u{201C}\(library.trimmedQuery)\u{201D}."
    }

    @ViewBuilder
    private var emptyMessage: some View {
        switch (player, library.section) {
        case (.appleMusic, _) where !library.hasAnyContent && !library.isPlayerRunning:
            MusicChooserMessage(
                title: "Your playlists, right here",
                detail: "Apple Music is closed. Load your library to pick something to play."
            ) {
                primaryButton("Load Library", systemImage: "music.note.list") {
                    library.loadLibraryLaunchingPlayer()
                }
            }
        case (.appleMusic, .collections):
            MusicChooserMessage(
                title: "No playlists yet",
                detail: "Playlists you make in Apple Music show up here."
            )
        case (.appleMusic, .songs):
            MusicChooserMessage(
                title: "No recently played songs",
                detail: "Search your library to find something."
            )
        case (.spotify, .collections):
            MusicChooserMessage(
                title: "Pin your playlists",
                detail: "In Spotify, choose Share \u{2192} Copy link on a playlist, album or song, then paste it here."
            ) {
                primaryButton("Paste a Link", systemImage: "link") { openPinField() }
            }
        case (.spotify, .songs):
            MusicChooserMessage(
                title: "Nothing played yet",
                detail: "Songs you play in Spotify show up here, ready to play again."
            )
        }
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(.white, in: Capsule())
        }
        .buttonStyle(MusicPressButtonStyle())
    }

    private func itemGrid(_ items: [MusicLibraryItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Self.rowSpacing),
                    GridItem(.flexible(), spacing: Self.rowSpacing),
                ],
                spacing: Self.rowSpacing
            ) {
                ForEach(items) { item in
                    MusicLibraryItemRow(
                        item: item,
                        artwork: library.artwork[item.id],
                        isPending: library.pendingItemID == item.id,
                        isDisabled: library.pendingItemID != nil && library.pendingItemID != item.id,
                        play: { library.play(item) }
                    )
                    .task(id: library.isPlayerRunning) {
                        library.requestArtwork(for: item)
                    }
                    .contextMenu { contextMenu(for: item) }
                }
            }
            .padding(.bottom, 4)
        }
        .mask {
            // Soft fade where rows scroll under the bottom edge.
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: .black.opacity(0.0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func contextMenu(for item: MusicLibraryItem) -> some View {
        Button("Play") { library.play(item) }
        if player == .spotify {
            if library.isPinned(item) {
                Button("Unpin") { library.unpin(item) }
            } else {
                Button("Pin") { library.pin(item) }
            }
            if library.songs.contains(where: { $0.id == item.id }) {
                Button("Remove from Recent") { library.forget(item) }
            }
            Divider()
            Button("Copy Spotify Link") {
                if let link = SpotifyLink.parse(item.id)?.webURL {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link.absoluteString, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private var statusToast: some View {
        if let message = library.statusMessage {
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5) }
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
        }
    }

    // MARK: Pinning

    private func openPinField() {
        library.endSearch()
        pinDraft = ""
        isPinFieldOpen = true
        focusedField = .pin
    }

    private func closePinField() {
        isPinFieldOpen = false
        pinDraft = ""
        if focusedField == .pin { focusedField = nil }
    }

    private func submitPin() {
        let text = pinDraft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch library.pin(link: text) {
        case .pinned, .alreadyPinned:
            closePinField()
        case .shortLink, .invalid:
            break
        }
    }
}

/// One playable thing: cover, title, subtitle. Hover dims the cover and
/// shows a play glyph; a pending play shows a spinner there instead.
struct MusicLibraryItemRow: View {
    let item: MusicLibraryItem
    let artwork: NSImage?
    let isPending: Bool
    let isDisabled: Bool
    let play: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 8) {
                cover
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(item.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.46))
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(height: MusicLibraryChooserView.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.08 : 0.035))
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(MusicPressButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help("Play \(item.title)")
        .accessibilityLabel("Play \(item.title), \(item.subtitle)")
    }

    private var cover: some View {
        let side = MusicLibraryChooserView.rowHeight - 8
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape.fill(.white.opacity(0.08))
                Image(systemName: item.kind.placeholderSymbol)
                    .font(.system(size: side * 0.4, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
            if isPending || isHovering {
                shape.fill(.black.opacity(0.45))
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: side * 0.36, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay { shape.stroke(.white.opacity(0.08), lineWidth: 0.5) }
    }
}

/// Centered title + detail (+ optional action) for an empty list.
struct MusicChooserMessage<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            accessory()
                .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                }
        }
    }
}

extension MusicChooserMessage where Accessory == EmptyView {
    init(title: String, detail: String?) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

/// Capsule control chrome: Liquid Glass on a glass panel, else a soft fill.
struct MusicCapsuleChrome: ViewModifier {
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if usesGlass, LiquidGlass.isSupported {
            content.islandGlass(in: Capsule())
        } else {
            content
                .background(.white.opacity(0.08), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5) }
        }
    }
}
