import Foundation

/// Localized string lookup for the app's UI strings. NotchTune ships
/// English only; strings still live in `en.lproj/Localizable.strings` so copy
/// stays in one place instead of scattered through the views.
@Observable
final class LanguageManager: @unchecked Sendable {
    static let shared = LanguageManager()

    private let bundle: Bundle

    /// Pre-English-only builds persisted a language choice here.
    private static let legacyDefaultsKey = "appLanguage"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
        self.bundle = Self.englishBundle()
    }

    // MARK: - Localized string access

    /// Look up a localized string by key.
    func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// Look up a localized format string and apply arguments.
    func t(_ key: String, _ args: any CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, arguments: args)
    }

    // MARK: - Private

    private static func englishBundle() -> Bundle {
        // SPM `.process()` may lowercase lproj directory names, and
        // Bundle.path(forResource:ofType:) is case-sensitive, so try both.
        for candidate in ["en", "En"] {
            if let path = Bundle.appResources.path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return Bundle.appResources
    }
}
