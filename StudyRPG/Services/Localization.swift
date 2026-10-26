import Foundation
import Observation
import SwiftUI

// MARK: - Localization (game.md §2 Language, §13 "Localization")
//
// Two String Catalogs: `Localizable.xcstrings` for every piece of UI text written in Swift, and
// `Content.xcstrings` for the names and texts in `Content/*.json`, keyed by their English text.
// The in-game language switches live: `Text("…")` literals follow the `\.locale` environment set by
// `.gameLocale()` at the root, and every `String` built in code goes through `L(…)`, which reads the
// observable language, so views that show it redraw when it changes.

/// The player's language choice. `system` follows the device (falling back to English).
nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german = "de"

    var id: String { rawValue }
}

/// Read from any thread (deck import validates cards off the main actor); only Settings writes it,
/// on the main actor.
@Observable
nonisolated final class Localization: @unchecked Sendable {
    static let shared = Localization()

    /// Languages the catalogs carry; the first is the development language.
    static let supportedCodes = ["en", "de"]
    private static let defaultsKey = "language"

    var language: AppLanguage {
        didSet {
            let defaults = UserDefaults.standard
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
            // System-provided text (photo picker, standard menu items) follows from the next launch.
            if language == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([language.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "") ?? .system
    }

    /// The language code actually shown ("en" or "de").
    var languageCode: String {
        if language != .system { return language.rawValue }
        return Bundle.preferredLocalizations(from: Self.supportedCodes, forPreferences: Locale.preferredLanguages).first ?? "en"
    }

    var locale: Locale { Locale(identifier: languageCode) }

    /// Each language's `.lproj` folder in the app bundle, for the content table.
    private static let languageBundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: supportedCodes.compactMap { code in
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)).map { (code, $0) }
    })

    /// A content text (`Content/*.json`) in the current language; untranslated text stays English.
    /// A plain table lookup, not a format string, so content may contain "%".
    func content(_ english: String) -> String { Self.content(english, in: languageCode) }

    /// A content text in a given language, or `nil` when that language doesn't translate it.
    static func translation(of english: String, in code: String) -> String? {
        let missing = "\u{0}missing"
        guard let bundle = languageBundles[code] else { return nil }
        let value = bundle.localizedString(forKey: english, value: missing, table: "Content")
        return value == missing ? nil : value
    }

    static func content(_ english: String, in code: String) -> String {
        guard !english.isEmpty else { return english }
        return translation(of: english, in: code) ?? english
    }
}

/// A UI string built in code, in the current language: `L("Step \(n) of \(total)")`.
nonisolated func L(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = Localization.shared.locale
    return String(localized: resource)
}

/// A content text field (a name, an event line): stored and saved as its English text, read in the
/// current language. Encodes as a plain string, so JSON and saved runs are unchanged.
@propertyWrapper
struct ContentText: Codable, Hashable {
    /// The English text from the content file — the catalog key.
    var key: String

    init(wrappedValue: String) { key = wrappedValue }

    var wrappedValue: String {
        get { Localization.shared.content(key) }
        set { key = newValue }
    }

    var projectedValue: String { key }

    init(from decoder: Decoder) throws {
        key = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// Sets the SwiftUI locale from the in-game language, so `Text("…")` literals switch with it.
private struct GameLocaleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.locale, Localization.shared.locale)
    }
}

extension View {
    /// Apply once at the root of every window or scene (game.md §2 Language).
    func gameLocale() -> some View { modifier(GameLocaleModifier()) }
}
