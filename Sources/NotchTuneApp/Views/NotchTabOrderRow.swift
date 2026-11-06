import SwiftUI
import UniformTypeIdentifiers

/// The notch's tabs as a row of chips, in order: drag one to move it. Moving
/// is also in each chip's context menu and its VoiceOver actions, since a
/// drag is the only way otherwise.
struct NotchTabOrderRow: View {
    @Binding var order: [IslandTab]
    let lang: LanguageManager

    @State private var dragged: IslandTab?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order) { tab in
                chip(tab)
                    .onDrag {
                        dragged = tab
                        return NSItemProvider(object: tab.rawValue as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: TabDropDelegate(target: tab, order: $order, dragged: $dragged)
                    )
                    .contextMenu {
                        Button(lang.t("settings.appearance.tabs.moveLeft")) { move(tab, by: -1) }
                            .disabled(tab == order.first)
                        Button(lang.t("settings.appearance.tabs.moveRight")) { move(tab, by: 1) }
                            .disabled(tab == order.last)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tab.title)
                    .accessibilityAction(named: lang.t("settings.appearance.tabs.moveLeft")) { move(tab, by: -1) }
                    .accessibilityAction(named: lang.t("settings.appearance.tabs.moveRight")) { move(tab, by: 1) }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ tab: IslandTab) -> some View {
        HStack(spacing: 5) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(tab.title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(SettingsTheme.paper.opacity(dragged == tab ? 0.45 : 0.9))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(SettingsTheme.paper.opacity(0.08), in: Capsule())
        .overlay { Capsule().stroke(SettingsTheme.paper.opacity(0.1), lineWidth: 0.5) }
        .contentShape(Capsule())
    }

    private func move(_ tab: IslandTab, by offset: Int) {
        withAnimation(.smooth(duration: 0.25)) {
            order = IslandTab.order(order, moving: tab, by: offset)
        }
    }
}

/// Reorders as the drag passes over each chip, so the row shows the result
/// before the drop.
private struct TabDropDelegate: DropDelegate {
    let target: IslandTab
    @Binding var order: [IslandTab]
    @Binding var dragged: IslandTab?

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        withAnimation(.smooth(duration: 0.25)) {
            order = IslandTab.order(order, moving: dragged, onto: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
