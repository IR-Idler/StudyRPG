import Foundation
import Observation
import SwiftUI
import CryptoKit

// MARK: - GameSettings (game.md §2 Settings)

/// Player preferences, stored in UserDefaults. Presentation only — never balance (that's JSON).
@Observable
final class GameSettings {
    private static let defaults = UserDefaults.standard

    /// Halves every combat pause, throws the dice harder, and batches an enemy's attack on both
    /// heroes into one throw (game.md §7.6).
    var fastMode: Bool { didSet { Self.defaults.set(fastMode, forKey: "fastMode") } }
    /// After a wrong answer, the quiz waits for a tap so the correct answer can be studied.
    var waitAfterWrongAnswer: Bool { didSet { Self.defaults.set(waitAfterWrongAnswer, forKey: "waitAfterWrongAnswer") } }
    /// After a right answer, the quiz also waits for a tap (off = it moves on immediately).
    var waitAfterRightAnswer: Bool { didSet { Self.defaults.set(waitAfterRightAnswer, forKey: "waitAfterRightAnswer") } }
    var haptics: Bool { didSet { Self.defaults.set(haptics, forKey: "haptics") } }
    /// Synthesized sound effects (game.md §19).
    var soundEffects: Bool {
        didSet {
            Self.defaults.set(soundEffects, forKey: "soundEffects")
            SoundEngine.shared.configure(enabled: soundEffects, volume: soundVolume)
        }
    }
    /// Effects volume, 0…1.
    var soundVolume: Double {
        didSet {
            Self.defaults.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.configure(enabled: soundEffects, volume: soundVolume)
        }
    }

    /// The in-game language (game.md §2 Language); lives in `Localization` so code anywhere can read it.
    var language: AppLanguage {
        get { Localization.shared.language }
        set { Localization.shared.language = newValue }
    }

    init() {
        Self.defaults.register(defaults: [
            "fastMode": false,
            "waitAfterWrongAnswer": true,
            "waitAfterRightAnswer": false,
            "haptics": true,
            "soundEffects": true,
            "soundVolume": 0.8
        ])
        fastMode = Self.defaults.bool(forKey: "fastMode")
        waitAfterWrongAnswer = Self.defaults.bool(forKey: "waitAfterWrongAnswer")
        waitAfterRightAnswer = Self.defaults.bool(forKey: "waitAfterRightAnswer")
        haptics = Self.defaults.bool(forKey: "haptics")
        soundEffects = Self.defaults.bool(forKey: "soundEffects")
        soundVolume = Self.defaults.double(forKey: "soundVolume")
    }

    /// Multiplier for every combat pause.
    var pace: Double { fastMode ? 0.5 : 1 }

    /// A pause in milliseconds, scaled by the current pace.
    func ms(_ normal: Int) -> Duration { .milliseconds(Int(Double(normal) * pace)) }
}
