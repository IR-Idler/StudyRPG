import Testing
@testable import StudyRPG

/// The synthesized sound effects (game.md §19) render to real, safe audio: never empty, never
/// NaN/infinite, never clipping past full scale, and short enough to stay snappy.
@Suite("Sound effects")
struct SoundTests {
    init() { Fixtures.isolateUserData() }

    @Test("Every sound effect renders finite, unclipped audio")
    func everySoundRenders() {
        for effect in SoundEffect.allCases {
            let variants = SoundSynth.render(effect)
            #expect(!variants.isEmpty, "\(effect) has no variants")
            for samples in variants {
                #expect(samples.count > 100, "\(effect) is empty")
                #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1 }, "\(effect) has invalid samples")
                #expect(samples.contains { abs($0) > 0.05 }, "\(effect) is silent")
                let seconds = Double(samples.count) / SynthBuffer.rate
                #expect(seconds < 6, "\(effect) is \(seconds)s long")
            }
        }
    }

    @Test("For now only button presses make a sound; everything else is muted (game.md §19)")
    func onlyButtonPressesPlay() {
        let audible = SoundEffect.allCases.filter { !$0.isMuted }
        #expect(audible == [.tap])
    }
}
