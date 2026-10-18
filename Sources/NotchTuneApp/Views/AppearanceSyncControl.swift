import SwiftUI

/// The Personalization display switcher, laid out like a car's dual-zone
/// climate panel: the two zones (MacBook notch, external display) on one
/// capsule track and a SYNC button with an indicator light beside it.
///
/// Off: the selection bezel sits on the zone being edited. On: the light
/// glows, the bezel stretches across both zones and a link joins them, so
/// every choice visibly lands on both. Picking one zone while synced turns
/// Sync off, as in a car.
struct AppearanceSyncControl: View {
    var model: AppModel

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: LanguageManager { model.lang }
    private var isSynced: Bool { model.appearanceSyncEnabled }

    var body: some View {
        HStack(spacing: 8) {
            zoneTrack
            syncButton
        }
        .fixedSize()
    }

    // MARK: - Zones

    private var zoneTrack: some View {
        HStack(spacing: 2) {
            zoneButton(.notch, title: lang.t("settings.appearance.profile.macbook.title"), systemImage: "laptopcomputer")
            if isSynced {
                Image(systemName: "link")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(SettingsTheme.positive)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            zoneButton(.topBar, title: lang.t("settings.appearance.profile.external.title"), systemImage: "display")
        }
        .background {
            // Synced: one bezel spans both zones (the same bezel morphs
            // out of the selected zone when Sync turns on).
            if isSynced {
                bezel.matchedGeometryEffect(id: "zone", in: namespace)
            }
        }
        .padding(2.5)
        .background(Capsule().fill(SettingsTheme.ink.opacity(0.45)))
        .overlay(Capsule().strokeBorder(SettingsTheme.paper.opacity(0.09), lineWidth: 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lang.t("settings.appearance.profile.title"))
        .accessibilityValue(isSynced ? lang.t("settings.appearance.sync.both") : zoneTitle(model.appearanceSettingsProfile))
        .accessibilityAdjustableAction { _ in
            select(model.appearanceSettingsProfile.other)
        }
    }

    private func zoneButton(_ profile: IslandAppearanceDisplayProfile, title: String, systemImage: String) -> some View {
        let isLit = isSynced || model.appearanceSettingsProfile == profile
        return Button {
            select(profile)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: isLit ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(SettingsTheme.paper.opacity(isLit ? 0.97 : 0.55))
            .padding(.horizontal, 11)
            .frame(height: 25)
            .background {
                if !isSynced, model.appearanceSettingsProfile == profile {
                    bezel.matchedGeometryEffect(id: "zone", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isSynced ? lang.t("settings.appearance.sync.zoneHelp") : lang.t("settings.appearance.profile.note"))
    }

    private var bezel: some View {
        IslandGlassBezel(shape: Capsule(), tint: isSynced ? SettingsTheme.positive : nil, isEmphasized: true)
    }

    private func zoneTitle(_ profile: IslandAppearanceDisplayProfile) -> String {
        profile == .notch
            ? lang.t("settings.appearance.profile.macbook.title")
            : lang.t("settings.appearance.profile.external.title")
    }

    // MARK: - Sync

    private var syncButton: some View {
        Button {
            withAnimation(animation) { model.setAppearanceSync(!isSynced) }
        } label: {
            HStack(spacing: 6) {
                // The indicator light: dark when off, lit and glowing on.
                Circle()
                    .fill(isSynced ? SettingsTheme.positive : SettingsTheme.paper.opacity(0.16))
                    .frame(width: 6, height: 6)
                    .shadow(color: SettingsTheme.positive.opacity(isSynced ? 0.9 : 0), radius: 3.5)
                Text(lang.t("settings.appearance.sync.title"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(SettingsTheme.paper.opacity(isSynced ? 0.97 : 0.62))
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background {
                Capsule().fill(isSynced ? SettingsTheme.positive.opacity(0.13) : SettingsTheme.ink.opacity(0.45))
            }
            .overlay {
                Capsule().strokeBorder(
                    isSynced ? SettingsTheme.positive.opacity(0.45) : SettingsTheme.paper.opacity(0.09),
                    lineWidth: 0.75
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(lang.t("settings.appearance.sync.help"))
        .accessibilityLabel(lang.t("settings.appearance.sync.title"))
        .accessibilityHint(lang.t("settings.appearance.sync.help"))
        .accessibilityAddTraits(isSynced ? [.isSelected] : [])
    }

    private func select(_ profile: IslandAppearanceDisplayProfile) {
        withAnimation(animation) { model.editAppearanceProfile(profile) }
    }

    private var animation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.32, extraBounce: 0.06)
    }
}
