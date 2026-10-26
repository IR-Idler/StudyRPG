import Foundation
import Testing
@testable import StudyRPG

/// Languages (game.md §2 Language, §13 "Localization"): every content text has a German entry,
/// content stays English in saved data, and code-built text switches with the language. Never
/// changes the player's language setting — tests run in parallel and share the app's defaults.
@MainActor
@Suite("Localization")
struct LocalizationTests {
    init() { Fixtures.isolateUserData() }

    /// Every content text as stored (its English key), from the real content files.
    private func contentTexts(_ content: GameContent) -> [String] {
        var texts: [String] = []
        for heroClass in content.classes {
            texts.append(heroClass.$name)
            if let resource = heroClass.resource { texts.append(resource.$name) }
            texts += heroClass.skills.map(\.$name)
        }
        for enemy in content.enemies {
            texts.append(enemy.$name)
            texts += enemy.usableSkills.map(\.$name)
            texts.append(enemy.basicAttack.$name)
        }
        texts += content.items.map(\.$name) + content.gear.map(\.$name) + content.relics.map(\.$name)
        texts += content.acts.map(\.$name) + content.events.map(\.$text)
        texts += content.balance.dice.stickers.map(\.$name)
        return texts
    }

    /// The starter decks' texts straight from `starter_decks.json` (the loaded decks are already
    /// in the current language).
    private func starterDeckTexts() throws -> [String] {
        let url = try #require(Bundle.main.url(forResource: "starter_decks", withExtension: "json", subdirectory: "Content")
            ?? Bundle.main.url(forResource: "starter_decks", withExtension: "json"))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let textFields: Set<String> = ["name", "subtitle", "prompt", "text", "hint", "explanation"]
        var texts: [String] = []
        func collect(_ value: Any) {
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if let text = child as? String, textFields.contains(key) { texts.append(text) } else { collect(child) }
                }
            } else if let array = value as? [Any] {
                array.forEach(collect)
            }
        }
        collect(root["decks"] ?? [])
        // Pure numbers and formulas ("7 × 8", "144") read the same in every language.
        return texts.filter { $0.contains(where: \.isLetter) }
    }

    @Test("Every content name and text has a German translation",
          .disabled("German is on hold until the translation pass (user decision 2026-10-27, agents.md)"))
    func contentIsTranslated() throws {
        let content = try Fixtures.content()
        let texts = contentTexts(content) + (try starterDeckTexts())
        #expect(!texts.isEmpty)
        let missing = Set(texts.filter { Localization.translation(of: $0, in: "de") == nil })
        #expect(missing.isEmpty, "Add these to Content/Content.xcstrings: \(missing.sorted())")
    }

    @Test("Content is saved by its English text, whatever the language")
    func contentEncodesAsKey() throws {
        let content = try Fixtures.content()
        let heroClass = try #require(content.classes.first)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(heroClass)) as? [String: Any])
        #expect(json["name"] as? String == heroClass.$name)
        let decoded = try JSONDecoder().decode(HeroClassDef.self, from: JSONEncoder().encode(heroClass))
        #expect(decoded.$name == heroClass.$name)
        // Reading the property gives the current language's text.
        #expect(heroClass.name == Localization.content(heroClass.$name, in: Localization.shared.languageCode))
    }

    @Test("German differs from English for content and for code-built text")
    func germanIsDifferent() throws {
        let content = try Fixtures.content()
        let texts = contentTexts(content)
        #expect(texts.contains { Localization.content($0, in: "de") != $0 })

        // A UI string with a number in it, resolved in German.
        let enemy = try #require(content.enemies.first)
        var resource = LocalizedStringResource("\(enemy.name) heals \(3) HP.")
        resource.locale = Locale(identifier: "en")
        let english = String(localized: resource)
        resource.locale = Locale(identifier: "de")
        let german = String(localized: resource)
        #expect(english != german)
        #expect(german.contains("3"))
    }

    @Test("Untranslated text falls back to English")
    func fallback() {
        let text = "Not a content text \(UUID().uuidString)"
        #expect(Localization.translation(of: text, in: "de") == nil)
        #expect(Localization.content(text, in: "de") == text)
    }
}
