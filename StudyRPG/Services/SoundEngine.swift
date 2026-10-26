import AVFoundation
import Foundation

// MARK: - Sound effects (game.md §19)
//
// Every sound is synthesized once at launch (on a background queue) from small DSP building
// blocks — struck "modal" partials for wood/metal/bells, filtered noise for whooshes, paper and
// fire, a soft brass voice for fanfares — then given a little offline reverb so it sits in the
// same moody, storybook space as the visuals. No audio files ship with the app.
//
// Playback is a small pool of AVAudioPlayerNodes on one AVAudioEngine. Everything runs on a
// private serial queue, so `Sound.play` is safe from any thread (the dice call it from
// SceneKit's render thread). The session is `.ambient`: the silent switch mutes the game and
// the player's own music keeps playing.

/// Every sound in the game. Presentation only — what triggers each one is listed in game.md §19.
nonisolated enum SoundEffect: String, CaseIterable, Sendable {
    // Interface — every button press uses the same `tap` so buttons sound identical
    case tap, deny
    // Flashcards
    case cardFlip, correct, wrong
    // Dice
    case diceThrow, diceClack, diceTotal
    // Attacks & impacts
    case slash, hit, block, claw, missile, fireball, fireBreath, laser
    // Effects
    case heal, mana, buff, debuff, stun, shield, potion
    // Run
    case coin, purchase, victory, defeat, footstep, skillLearn
    // Loops
    case campfire

    /// Muted for now (user decision 2026-10-26, game.md §19): only button presses (`tap`) play.
    /// Every other sound is still synthesized and tested, just never played.
    var isMuted: Bool { self != .tap }

    /// Loudness relative to the master volume, so quiet ambience doesn't drown out hits.
    fileprivate var gain: Float {
        switch self {
        case .tap: return 0.3
        case .footstep: return 0.45
        case .diceClack: return 0.55
        case .campfire: return 0.5
        case .cardFlip, .diceThrow: return 0.6
        case .victory, .defeat, .fireball: return 0.9
        default: return 0.75
        }
    }
}

/// Fire-and-forget entry point used throughout the views.
nonisolated enum Sound {
    static func play(_ effect: SoundEffect, volume: Float = 1, delay: Double = 0) {
        guard !effect.isMuted else { return }
        SoundEngine.shared.play(effect, volume: volume, delay: delay)
    }

    static func startLoop(_ effect: SoundEffect) {
        guard !effect.isMuted else { return }
        SoundEngine.shared.startLoop(effect)
    }
    static func stopLoop() { SoundEngine.shared.stopLoop() }
}

nonisolated final class SoundEngine: @unchecked Sendable {
    static let shared = SoundEngine()

    private let queue = DispatchQueue(label: "StudyRPG.sound", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SynthBuffer.rate, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private let loopVoice = AVAudioPlayerNode()
    private var loopEffect: SoundEffect?
    private var buffers: [SoundEffect: [AVAudioPCMBuffer]] = [:]
    private var isReady = false
    private var enabled = true
    private var volume: Float = 0.8
    /// Last time each effect started, so a burst of identical triggers (dice clacks, steps)
    /// doesn't stack into one loud smear.
    private var lastPlayed: [SoundEffect: CFTimeInterval] = [:]

    private init() {}

    /// Builds every buffer and starts the engine. Call once at launch; cheap to call again.
    func prepare(enabled: Bool, volume: Double) {
        queue.async { [self] in
            self.enabled = enabled
            self.volume = Float(volume)
            guard !isReady else { applyVolume(); return }

            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)
            #endif

            for _ in 0..<10 {
                let voice = AVAudioPlayerNode()
                engine.attach(voice)
                try? engine.connectNode(voice, to: engine.mainMixerNode, format: format)
                voices.append(voice)
            }
            engine.attach(loopVoice)
            try? engine.connectNode(loopVoice, to: engine.mainMixerNode, format: format)
            applyVolume()

            for effect in SoundEffect.allCases {
                buffers[effect] = SoundSynth.render(effect).compactMap(makeBuffer)
            }
            NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                self?.queue.async { self?.startEngineIfNeeded() }
            }
            #if os(iOS)
            NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async { self?.startEngineIfNeeded() }
            }
            #endif
            isReady = true
            startEngineIfNeeded()
        }
    }

    func configure(enabled: Bool, volume: Double) {
        queue.async { [self] in
            self.enabled = enabled
            self.volume = Float(volume)
            applyVolume()
            if !enabled { loopVoice.stop() } else if let loopEffect { startLoopLocked(loopEffect) }
        }
    }

    func play(_ effect: SoundEffect, volume: Float = 1, delay: Double = 0) {
        let fire: @Sendable () -> Void = { [self] in
            guard isReady, enabled, self.volume > 0, let variants = buffers[effect], let buffer = variants.randomElement() else { return }
            let now = CACurrentMediaTime()
            if let last = lastPlayed[effect], now - last < 0.035 { return }
            lastPlayed[effect] = now
            startEngineIfNeeded()
            guard engine.isRunning else { return }
            let voice = voices[nextVoice]
            nextVoice = (nextVoice + 1) % voices.count
            voice.stop()
            voice.volume = min(1, max(0, volume)) * effect.gain
            voice.scheduleBuffer(buffer, at: nil, options: [])
            try? voice.playAudio()
        }
        if delay > 0 {
            queue.asyncAfter(deadline: .now() + delay, execute: fire)
        } else {
            queue.async(execute: fire)
        }
    }

    func startLoop(_ effect: SoundEffect) {
        queue.async { [self] in
            loopEffect = effect
            startLoopLocked(effect)
        }
    }

    func stopLoop() {
        queue.async { [self] in
            loopEffect = nil
            loopVoice.stop()
        }
    }

    // MARK: Queue-only helpers

    private func startLoopLocked(_ effect: SoundEffect) {
        guard isReady, enabled, let buffer = buffers[effect]?.first else { return }
        startEngineIfNeeded()
        guard engine.isRunning else { return }
        loopVoice.stop()
        loopVoice.volume = effect.gain
        loopVoice.scheduleBuffer(buffer, at: nil, options: [.loops])
        try? loopVoice.playAudio()
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = enabled ? volume : 0
    }

    private func startEngineIfNeeded() {
        guard isReady, !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

// MARK: - DSP building blocks

/// A mono sample buffer plus the handful of operations every sound is built from.
nonisolated struct SynthBuffer {
    static let rate: Double = 44_100
    var samples: [Double]

    init(seconds: Double) {
        samples = Array(repeating: 0, count: max(1, Int(seconds * Self.rate)))
    }

    var duration: Double { Double(samples.count) / Self.rate }

    /// Runs `generate(t)` for every sample from `start` for `length` seconds and mixes it in.
    mutating func add(at start: Double, length: Double, _ generate: (Double) -> Double) {
        let first = max(0, Int(start * Self.rate))
        let last = min(samples.count, Int((start + length) * Self.rate))
        guard first < last else { return }
        for i in first..<last {
            samples[i] += generate(Double(i - first) / Self.rate)
        }
    }

    /// A struck object: inharmonic partials `(ratio, amplitude, decay seconds)` over a base pitch.
    mutating func strike(at start: Double, freq: Double, partials: [(Double, Double, Double)], amp: Double, attack: Double = 0.002) {
        let longest = partials.map(\.2).max() ?? 0.2
        add(at: start, length: longest * 6) { t in
            let a = t < attack ? t / attack : 1
            var sum = 0.0
            for (ratio, level, decay) in partials {
                sum += level * exp(-t / decay) * sin(2 * .pi * freq * ratio * t)
            }
            return sum * amp * a
        }
    }

    /// Soft bell / glockenspiel note.
    mutating func bell(at start: Double, freq: Double, amp: Double, decay: Double = 0.5) {
        strike(at: start, freq: freq, partials: [(1, 1, decay), (2.76, 0.32, decay * 0.3), (5.4, 0.12, decay * 0.12), (2.0, 0.18, decay * 0.5)], amp: amp, attack: 0.003)
    }

    /// Wooden marimba-like pluck.
    mutating func pluck(at start: Double, freq: Double, amp: Double) {
        strike(at: start, freq: freq, partials: [(1, 1, 0.22), (3.9, 0.22, 0.04), (9.8, 0.06, 0.012)], amp: amp, attack: 0.001)
    }

    /// A soft brass-like voice: band-limited saw through a lowpass that opens with the envelope.
    mutating func brass(at start: Double, freq: Double, length: Double, amp: Double) {
        var phase = 0.0
        var filter = OnePole()
        add(at: start, length: length + 0.4) { t in
            let env = t < 0.04 ? t / 0.04 : (t < length ? 1 - 0.25 * (t - 0.04) / max(0.01, length) : 0.75 * exp(-(t - length) / 0.12))
            let vibrato = 1 + 0.004 * sin(2 * .pi * 5.5 * t) * min(1, t / 0.3)
            phase += freq * vibrato / Self.rate
            var saw = 0.0
            for h in 1...8 {
                saw += sin(2 * .pi * phase * Double(h)) / Double(h)
            }
            let cutoff = 500 + 3200 * env
            return filter.lowpass(saw * 0.6, cutoff: cutoff) * env * amp
        }
    }

    /// Filtered noise with a time-varying band-pass center and an amplitude envelope.
    mutating func noise(at start: Double, length: Double, seed: UInt32, amp: Double, resonance: Double = 0.6,
                        cutoff: (Double) -> Double, envelope: (Double) -> Double) {
        var rng = NoiseSource(seed: seed)
        var svf = StateVariableFilter()
        add(at: start, length: length) { t in
            let band = svf.process(rng.next(), cutoff: cutoff(t), damping: resonance).band
            return band * envelope(t) * amp
        }
    }

    /// Low-passed noise (rumble, thumps, breath).
    mutating func lowNoise(at start: Double, length: Double, seed: UInt32, amp: Double,
                           cutoff: (Double) -> Double, envelope: (Double) -> Double) {
        var rng = NoiseSource(seed: seed)
        var filter = OnePole()
        add(at: start, length: length) { t in
            filter.lowpass(rng.next(), cutoff: cutoff(t)) * envelope(t) * amp
        }
    }

    /// A pitched thump that drops in pitch (drums, body hits).
    mutating func thump(at start: Double, from high: Double, to low: Double, drop: Double, decay: Double, amp: Double) {
        var phase = 0.0
        add(at: start, length: decay * 6) { t in
            let f = low + (high - low) * exp(-t / drop)
            phase += f / Self.rate
            let a = t < 0.002 ? t / 0.002 : exp(-t / decay)
            return sin(2 * .pi * phase) * a * amp
        }
    }

    /// Short crackling pops scattered over a span (fire, embers).
    mutating func crackle(at start: Double, length: Double, perSecond: Double, seed: UInt32, amp: Double) {
        var rng = NoiseSource(seed: seed)
        let count = Int(length * perSecond)
        for _ in 0..<count {
            let when = start + rng.unit() * length
            let freq = 1800 + rng.unit() * 3800
            let level = amp * (0.3 + 0.7 * rng.unit() * rng.unit())
            let popSeed = UInt32(truncatingIfNeeded: Int(rng.unit() * 1_000_000))
            noise(at: when, length: 0.03, seed: popSeed, amp: level, resonance: 0.4, cutoff: { _ in freq }, envelope: { t in exp(-t / 0.004) })
        }
    }

    /// Offline Schroeder reverb (4 damped combs + 2 allpasses) — the shared "stone hall".
    mutating func reverb(wet: Double, size: Double = 1) {
        guard wet > 0 else { return }
        let tail = Int(0.9 * size * Self.rate)
        let dry = samples + Array(repeating: 0, count: tail)
        var out = Array(repeating: 0.0, count: dry.count)
        let combDelays = [1116, 1188, 1277, 1356].map { Int(Double($0) * size) }
        for delay in combDelays {
            var buffer = Array(repeating: 0.0, count: delay)
            var index = 0
            var damp = 0.0
            for i in 0..<dry.count {
                let y = buffer[index]
                damp = y * 0.7 + damp * 0.3
                buffer[index] = dry[i] + damp * 0.8
                index = (index + 1) % delay
                out[i] += y * 0.25
            }
        }
        for delay in [556, 441] {
            var buffer = Array(repeating: 0.0, count: delay)
            var index = 0
            for i in 0..<out.count {
                let b = buffer[index]
                let y = -out[i] + b
                buffer[index] = out[i] + b * 0.5
                index = (index + 1) % delay
                out[i] = y
            }
        }
        samples = zip(dry, out).map { $0 + $1 * wet }
    }

    /// Scales to the target peak, trims trailing silence and fades the last few ms.
    func finished(peak: Double = 0.85) -> [Float] {
        var end = samples.count
        while end > 1, abs(samples[end - 1]) < 0.0004 { end -= 1 }
        let body = samples[0..<end]
        let maxValue = body.map(abs).max() ?? 0
        let scale = maxValue > 0 ? peak / maxValue : 0
        let fade = min(256, end)
        return body.enumerated().map { i, s in
            let tailFade = i >= end - fade ? Double(end - i) / Double(fade) : 1
            return Float(s * scale * tailFade)
        }
    }

    /// The same sound played faster/slower (pitch variants without extra synthesis).
    static func resample(_ source: [Float], ratio: Double) -> [Float] {
        let count = Int(Double(source.count) / ratio)
        guard count > 1 else { return source }
        return (0..<count).map { i in
            let position = Double(i) * ratio
            let index = Int(position)
            let frac = Float(position - Double(index))
            let a = source[min(index, source.count - 1)]
            let b = source[min(index + 1, source.count - 1)]
            return a + (b - a) * frac
        }
    }
}

/// Deterministic white noise (so every launch sounds the same).
nonisolated struct NoiseSource {
    private var state: UInt32
    init(seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }
    mutating func unit() -> Double { (next() + 1) / 2 }
}

nonisolated struct OnePole {
    var y = 0.0
    mutating func lowpass(_ x: Double, cutoff: Double) -> Double {
        let a = 1 - exp(-2 * .pi * min(cutoff, 18_000) / SynthBuffer.rate)
        y += a * (x - y)
        return y
    }
}

/// Chamberlin state-variable filter (low/band/high at once).
nonisolated struct StateVariableFilter {
    var low = 0.0, band = 0.0
    mutating func process(_ x: Double, cutoff: Double, damping: Double) -> (low: Double, band: Double, high: Double) {
        let f = 2 * sin(.pi * min(max(cutoff, 20), 7_000) / SynthBuffer.rate)
        low += f * band
        let high = x - low - damping * band
        band += f * high
        return (low, band, high)
    }
}

/// Envelope helpers: attack ramp, then exponential decay.
nonisolated func ad(_ t: Double, attack: Double, decay: Double) -> Double {
    t < attack ? t / attack : exp(-(t - attack) / decay)
}

/// A smooth hump over `length` seconds (whooshes).
nonisolated func hump(_ t: Double, length: Double, peakAt: Double = 0.5) -> Double {
    guard t >= 0, t <= length else { return 0 }
    let u = t / length
    return u < peakAt ? sin(.pi / 2 * u / peakAt) : cos(.pi / 2 * (u - peakAt) / (1 - peakAt))
}

/// Exponential sweep from `a` to `b` over `length` seconds.
nonisolated func sweep(_ t: Double, from a: Double, to b: Double, over length: Double) -> Double {
    a * pow(b / a, min(1, max(0, t / length)))
}

// MARK: - The sound recipes

nonisolated enum SoundSynth {
    /// One or more variants of a sound (variants are picked at random on play).
    static func render(_ effect: SoundEffect) -> [[Float]] {
        switch effect {
        case .tap:
            // A soft, muffled wooden "tock": low and short, no bright partials, so pressing
            // buttons all the time doesn't grate.
            var b = SynthBuffer(seconds: 0.1)
            b.strike(at: 0, freq: 330, partials: [(1, 1, 0.028), (2.1, 0.25, 0.012)], amp: 1, attack: 0.003)
            b.lowNoise(at: 0, length: 0.03, seed: 7, amp: 0.35, cutoff: { _ in 900 }, envelope: { ad($0, attack: 0.002, decay: 0.006) })
            return [b.finished(peak: 0.45)]

        case .deny:
            var b = SynthBuffer(seconds: 0.35)
            b.thump(at: 0, from: 260, to: 150, drop: 0.03, decay: 0.05, amp: 1)
            b.thump(at: 0.1, from: 230, to: 130, drop: 0.03, decay: 0.06, amp: 0.9)
            return [b.finished(peak: 0.6)]

        case .cardFlip:
            var b = SynthBuffer(seconds: 0.3)
            b.noise(at: 0, length: 0.2, seed: 11, amp: 1, resonance: 1.2,
                    cutoff: { sweep($0, from: 1400, to: 5200, over: 0.15) },
                    envelope: { hump($0, length: 0.18, peakAt: 0.25) * (0.65 + 0.35 * sin(2 * .pi * 36 * $0)) })
            b.noise(at: 0.11, length: 0.08, seed: 12, amp: 0.5, resonance: 1.0,
                    cutoff: { _ in 2600 }, envelope: { exp(-$0 / 0.02) })
            return variants(b.finished(peak: 0.55), [0.92, 1.05])

        case .correct:
            var b = SynthBuffer(seconds: 1.2)
            b.bell(at: 0, freq: 1046.5, amp: 0.7, decay: 0.5)
            b.bell(at: 0.07, freq: 1318.5, amp: 0.7, decay: 0.5)
            b.bell(at: 0.14, freq: 1568.0, amp: 0.85, decay: 0.7)
            b.reverb(wet: 0.3)
            return [b.finished(peak: 0.7)]

        case .wrong:
            var b = SynthBuffer(seconds: 0.8)
            b.thump(at: 0, from: 160, to: 70, drop: 0.05, decay: 0.12, amp: 0.8)
            var filter = OnePole()
            b.add(at: 0.01, length: 0.6) { t in
                let tri = { (f: Double) -> Double in 2 * abs(2 * (t * f - floor(t * f + 0.5))) - 1 }
                return filter.lowpass(tri(196) + tri(207.6), cutoff: 1100) * ad(t, attack: 0.006, decay: 0.2) * 0.6
            }
            b.reverb(wet: 0.2)
            return [b.finished(peak: 0.7)]

        case .diceThrow:
            var b = SynthBuffer(seconds: 0.35)
            b.noise(at: 0, length: 0.3, seed: 21, amp: 1, resonance: 1.1,
                    cutoff: { sweep($0, from: 500, to: 2200, over: 0.25) },
                    envelope: { hump($0, length: 0.28, peakAt: 0.6) })
            return [b.finished(peak: 0.5)]

        case .diceClack:
            var b = SynthBuffer(seconds: 0.12)
            b.strike(at: 0, freq: 1900, partials: [(1, 1, 0.018), (1.68, 0.6, 0.012), (2.5, 0.4, 0.008)], amp: 1)
            b.thump(at: 0, from: 420, to: 260, drop: 0.01, decay: 0.012, amp: 0.6)
            b.noise(at: 0, length: 0.01, seed: 31, amp: 0.5, cutoff: { _ in 5000 }, envelope: { exp(-$0 / 0.0015) })
            return variants(b.finished(peak: 0.8), [0.85, 0.95, 1.05, 1.17])

        case .diceTotal:
            var b = SynthBuffer(seconds: 0.5)
            b.strike(at: 0, freq: 880, partials: [(1, 1, 0.12), (2.0, 0.4, 0.06), (3.0, 0.2, 0.03)], amp: 0.7)
            b.thump(at: 0, from: 180, to: 90, drop: 0.03, decay: 0.07, amp: 0.7)
            b.reverb(wet: 0.15)
            return [b.finished(peak: 0.6)]

        case .slash:
            var b = SynthBuffer(seconds: 0.7)
            b.noise(at: 0, length: 0.22, seed: 41, amp: 1, resonance: 0.5,
                    cutoff: { sweep($0, from: 700, to: 5600, over: 0.16) },
                    envelope: { hump($0, length: 0.2, peakAt: 0.55) })
            b.strike(at: 0.09, freq: 2950, partials: [(1, 0.5, 0.22), (1.5, 0.35, 0.16), (2.1, 0.2, 0.1)], amp: 0.35, attack: 0.01)
            b.noise(at: 0.12, length: 0.25, seed: 42, amp: 0.5, resonance: 0.5,
                    cutoff: { sweep($0, from: 4800, to: 1800, over: 0.2) },
                    envelope: { hump($0, length: 0.22, peakAt: 0.2) })
            b.reverb(wet: 0.12)
            return variants(b.finished(peak: 0.8), [0.95, 1.05])

        case .hit:
            var b = SynthBuffer(seconds: 0.4)
            b.thump(at: 0, from: 150, to: 48, drop: 0.045, decay: 0.11, amp: 1)
            b.lowNoise(at: 0, length: 0.15, seed: 51, amp: 0.9, cutoff: { _ in 1000 }, envelope: { exp(-$0 / 0.028) })
            b.noise(at: 0, length: 0.05, seed: 52, amp: 0.35, cutoff: { _ in 2600 }, envelope: { exp(-$0 / 0.008) })
            return variants(b.finished(peak: 0.9), [0.9, 1, 1.1])

        case .block:
            var b = SynthBuffer(seconds: 1.2)
            b.strike(at: 0, freq: 640, partials: [(1, 1, 0.5), (2.37, 0.7, 0.32), (3.72, 0.5, 0.22), (5.5, 0.35, 0.15), (7.4, 0.2, 0.08)], amp: 0.6)
            b.noise(at: 0, length: 0.02, seed: 61, amp: 0.6, cutoff: { _ in 5500 }, envelope: { exp(-$0 / 0.003) })
            b.thump(at: 0, from: 200, to: 110, drop: 0.02, decay: 0.05, amp: 0.4)
            b.reverb(wet: 0.2)
            return variants(b.finished(peak: 0.7), [0.94, 1.06])

        case .claw:
            var b = SynthBuffer(seconds: 0.6)
            for (index, start) in [0.0, 0.065, 0.13].enumerated() {
                b.noise(at: start, length: 0.09, seed: UInt32(71 + index), amp: 0.9, resonance: 0.45,
                        cutoff: { sweep($0, from: 3600, to: 1100, over: 0.08) },
                        envelope: { hump($0, length: 0.085, peakAt: 0.3) })
            }
            var growlPhase = 0.0
            var filter = OnePole()
            b.add(at: 0, length: 0.4) { t in
                growlPhase += (72 + 10 * sin(2 * .pi * 3 * t)) / SynthBuffer.rate
                let saw = 2 * (growlPhase - floor(growlPhase)) - 1
                let flutter = 0.7 + 0.3 * sin(2 * .pi * 23 * t)
                return filter.lowpass(saw, cutoff: 550) * ad(t, attack: 0.03, decay: 0.16) * flutter * 0.7
            }
            b.reverb(wet: 0.1)
            return variants(b.finished(peak: 0.85), [0.92, 1.06])

        case .missile:
            var b = SynthBuffer(seconds: 0.9)
            var phase = 0.0, phase2 = 0.0
            b.add(at: 0, length: 0.36) { t in
                let f = sweep(t, from: 520, to: 1500, over: 0.3) * (1 + 0.05 * sin(2 * .pi * 18 * t))
                phase += f / SynthBuffer.rate
                phase2 += f * 1.5 / SynthBuffer.rate
                return (sin(2 * .pi * phase) + 0.4 * sin(2 * .pi * phase2)) * ad(t, attack: 0.02, decay: 0.22) * 0.5
            }
            var rng = NoiseSource(seed: 81)
            for _ in 0..<14 {
                b.bell(at: rng.unit() * 0.3, freq: 2800 + rng.unit() * 3000, amp: 0.12, decay: 0.05)
            }
            b.noise(at: 0.32, length: 0.15, seed: 82, amp: 0.7, resonance: 0.7, cutoff: { _ in 1900 }, envelope: { exp(-$0 / 0.035) })
            b.bell(at: 0.32, freq: 1760, amp: 0.3, decay: 0.2)
            b.reverb(wet: 0.28)
            return [b.finished(peak: 0.7)]

        case .fireball:
            // Charge + flight (0…0.52s), then the explosion lands exactly when the VFX impacts.
            var b = SynthBuffer(seconds: 1.6)
            b.lowNoise(at: 0, length: 0.55, seed: 91, amp: 1,
                       cutoff: { sweep($0, from: 300, to: 3200, over: 0.5) },
                       envelope: { pow(min(1, $0 / 0.5), 1.6) * (0.8 + 0.2 * sin(2 * .pi * 13 * $0)) })
            b.crackle(at: 0.1, length: 0.42, perSecond: 40, seed: 92, amp: 0.25)
            let impact = 0.52
            b.lowNoise(at: impact, length: 1.0, seed: 93, amp: 1.4,
                       cutoff: { 150 + 4200 * exp(-$0 / 0.14) },
                       envelope: { ad($0, attack: 0.004, decay: 0.32) })
            b.thump(at: impact, from: 90, to: 32, drop: 0.12, decay: 0.3, amp: 1.2)
            b.crackle(at: impact + 0.05, length: 0.6, perSecond: 30, seed: 94, amp: 0.35)
            b.reverb(wet: 0.3, size: 1.2)
            return [b.finished(peak: 0.92)]

        case .fireBreath:
            var b = SynthBuffer(seconds: 1.2)
            b.noise(at: 0, length: 0.8, seed: 101, amp: 1, resonance: 0.8,
                    cutoff: { 500 + 400 * sin(2 * .pi * 2.5 * $0) },
                    envelope: { hump($0, length: 0.78, peakAt: 0.25) * (0.75 + 0.15 * sin(2 * .pi * 11 * $0) + 0.1 * sin(2 * .pi * 17 * $0)) })
            b.lowNoise(at: 0, length: 0.8, seed: 102, amp: 0.8, cutoff: { _ in 260 },
                       envelope: { hump($0, length: 0.78, peakAt: 0.2) })
            b.crackle(at: 0.05, length: 0.7, perSecond: 45, seed: 103, amp: 0.3)
            b.reverb(wet: 0.25)
            return [b.finished(peak: 0.85)]

        case .laser:
            // A short rising charge, then a bright falling zap with a buzzing edge.
            var b = SynthBuffer(seconds: 0.8)
            var phase = 0.0
            b.add(at: 0, length: 0.13) { t in
                phase += sweep(t, from: 600, to: 2400, over: 0.13) / SynthBuffer.rate
                return sin(2 * .pi * phase) * hump(t, length: 0.13, peakAt: 0.9) * 0.25
            }
            var zap = 0.0, buzz = 0.0
            b.add(at: 0.13, length: 0.45) { t in
                zap += sweep(t, from: 2600, to: 420, over: 0.32) / SynthBuffer.rate
                buzz += 90 / SynthBuffer.rate
                let square = sin(2 * .pi * zap) > 0 ? 1.0 : -1.0
                let tone = 0.55 * sin(2 * .pi * zap) + 0.2 * square * (0.6 + 0.4 * sin(2 * .pi * buzz))
                return tone * ad(t, attack: 0.004, decay: 0.16)
            }
            b.noise(at: 0.13, length: 0.12, seed: 171, amp: 0.4, resonance: 0.6, cutoff: { _ in 5200 }, envelope: { exp(-$0 / 0.03) })
            b.reverb(wet: 0.18)
            return variants(b.finished(peak: 0.75), [0.95, 1.06])

        case .heal:
            var b = SynthBuffer(seconds: 1.8)
            for (index, freq) in [523.3, 659.3, 784.0, 1046.5, 1318.5].enumerated() {
                let start = Double(index) * 0.075
                for detune in [0.997, 1.003] {
                    b.add(at: start, length: 1.0) { t in
                        sin(2 * .pi * freq * detune * t) * ad(t, attack: 0.025, decay: 0.38) * 0.22
                    }
                }
            }
            b.noise(at: 0, length: 0.7, seed: 111, amp: 0.25, resonance: 1.2, cutoff: { _ in 6000 },
                    envelope: { hump($0, length: 0.7, peakAt: 0.4) })
            b.reverb(wet: 0.42, size: 1.1)
            return [b.finished(peak: 0.65)]

        case .mana:
            var b = SynthBuffer(seconds: 1.4)
            for (index, freq) in [1760.0, 2637.0, 3520.0].enumerated() {
                b.strike(at: Double(index) * 0.05, freq: freq, partials: [(1, 1, 0.4), (2.32, 0.35, 0.15), (4.25, 0.15, 0.06)], amp: 0.5)
            }
            b.reverb(wet: 0.38)
            return [b.finished(peak: 0.6)]

        case .buff:
            var b = SynthBuffer(seconds: 1.0)
            b.thump(at: 0, from: 120, to: 55, drop: 0.05, decay: 0.15, amp: 0.9)
            b.brass(at: 0.02, freq: 220, length: 0.3, amp: 0.4)
            b.brass(at: 0.02, freq: 277.2, length: 0.3, amp: 0.35)
            b.brass(at: 0.02, freq: 329.6, length: 0.3, amp: 0.35)
            b.reverb(wet: 0.25)
            return [b.finished(peak: 0.75)]

        case .debuff:
            var b = SynthBuffer(seconds: 1.0)
            var phase = 0.0
            var filter = OnePole()
            b.add(at: 0, length: 0.6) { t in
                let f = sweep(t, from: 440, to: 200, over: 0.45) * (1 + 0.03 * sin(2 * .pi * 7 * t))
                phase += f / SynthBuffer.rate
                let tri = 2 * abs(2 * (phase - floor(phase + 0.5))) - 1
                return filter.lowpass(tri + 0.5 * sin(2 * .pi * phase * 0.5), cutoff: 1400) * ad(t, attack: 0.02, decay: 0.28) * 0.7
            }
            b.reverb(wet: 0.3)
            return [b.finished(peak: 0.65)]

        case .stun:
            var b = SynthBuffer(seconds: 0.8)
            b.thump(at: 0, from: 200, to: 90, drop: 0.03, decay: 0.08, amp: 0.7)
            for (index, start) in [0.05, 0.15, 0.25].enumerated() {
                var phase = 0.0
                let top = 2400 - Double(index) * 300
                b.add(at: start, length: 0.09) { t in
                    phase += sweep(t, from: top, to: top * 0.6, over: 0.08) / SynthBuffer.rate
                    return sin(2 * .pi * phase) * hump(t, length: 0.085, peakAt: 0.2) * 0.35
                }
            }
            b.reverb(wet: 0.25)
            return [b.finished(peak: 0.6)]

        case .shield:
            var b = SynthBuffer(seconds: 1.4)
            b.noise(at: 0, length: 0.25, seed: 121, amp: 0.6, resonance: 0.9,
                    cutoff: { sweep($0, from: 300, to: 1600, over: 0.2) }, envelope: { hump($0, length: 0.24, peakAt: 0.7) })
            b.thump(at: 0.18, from: 160, to: 80, drop: 0.03, decay: 0.08, amp: 0.6)
            b.strike(at: 0.18, freq: 880, partials: [(1, 1, 0.6), (1.5, 0.5, 0.4), (2.38, 0.3, 0.25)], amp: 0.3, attack: 0.015)
            b.reverb(wet: 0.3)
            return [b.finished(peak: 0.65)]

        case .potion:
            var b = SynthBuffer(seconds: 1.0)
            for (start, base) in [(0.0, 340.0), (0.09, 420.0), (0.17, 380.0), (0.26, 460.0)] {
                var phase = 0.0
                b.add(at: start, length: 0.07) { t in
                    phase += base * exp(t / 0.035) / SynthBuffer.rate
                    return sin(2 * .pi * phase) * hump(t, length: 0.065, peakAt: 0.15) * 0.6
                }
            }
            b.bell(at: 0.36, freq: 1568, amp: 0.25, decay: 0.3)
            b.bell(at: 0.4, freq: 2093, amp: 0.2, decay: 0.3)
            b.reverb(wet: 0.25)
            return [b.finished(peak: 0.65)]

        case .coin:
            var b = SynthBuffer(seconds: 0.9)
            b.strike(at: 0, freq: 1975.5, partials: [(1, 1, 0.12), (2.4, 0.4, 0.06), (3.9, 0.2, 0.03)], amp: 0.6)
            b.strike(at: 0.07, freq: 2637, partials: [(1, 1, 0.35), (2.4, 0.4, 0.12), (3.9, 0.2, 0.05)], amp: 0.7)
            b.reverb(wet: 0.15)
            return [b.finished(peak: 0.55)]

        case .purchase:
            var b = SynthBuffer(seconds: 1.0)
            var rng = NoiseSource(seed: 131)
            for _ in 0..<7 {
                b.strike(at: rng.unit() * 0.28, freq: 2100 + rng.unit() * 1900, partials: [(1, 1, 0.08), (2.4, 0.4, 0.04)], amp: 0.35)
            }
            b.strike(at: 0.3, freq: 2637, partials: [(1, 1, 0.35), (2.4, 0.4, 0.12)], amp: 0.6)
            b.reverb(wet: 0.18)
            return [b.finished(peak: 0.6)]

        case .victory:
            var b = SynthBuffer(seconds: 3.0)
            b.brass(at: 0.0, freq: 392.0, length: 0.13, amp: 0.5)
            b.brass(at: 0.15, freq: 523.3, length: 0.13, amp: 0.5)
            b.brass(at: 0.30, freq: 659.3, length: 0.13, amp: 0.5)
            b.brass(at: 0.45, freq: 784.0, length: 0.95, amp: 0.55)
            b.brass(at: 0.45, freq: 659.3, length: 0.95, amp: 0.35)
            b.brass(at: 0.45, freq: 523.3, length: 0.95, amp: 0.3)
            b.thump(at: 0.45, from: 110, to: 60, drop: 0.06, decay: 0.4, amp: 0.8)
            b.lowNoise(at: 0.45, length: 0.6, seed: 141, amp: 0.4, cutoff: { _ in 400 }, envelope: { exp(-$0 / 0.15) })
            for (index, freq) in [1568.0, 2093.0, 2637.0].enumerated() {
                b.bell(at: 0.5 + Double(index) * 0.08, freq: freq, amp: 0.15, decay: 0.6)
            }
            b.reverb(wet: 0.35, size: 1.2)
            return [b.finished(peak: 0.85)]

        case .defeat:
            var b = SynthBuffer(seconds: 4.0)
            b.thump(at: 0, from: 90, to: 45, drop: 0.08, decay: 0.5, amp: 0.8)
            for (start, freq, length) in [(0.0, 220.0, 0.45), (0.45, 174.6, 0.45), (0.9, 146.8, 0.45), (1.35, 138.6, 1.2)] {
                for (ratio, level) in [(1.0, 0.5), (2.0, 0.12), (0.5, 0.25)] {
                    b.add(at: start, length: length + 0.8) { t in
                        let env = t < 0.08 ? t / 0.08 : (t < length ? 1 : exp(-(t - length) / 0.3))
                        let vibrato = 1 + 0.003 * sin(2 * .pi * 5 * t)
                        return sin(2 * .pi * freq * ratio * vibrato * t) * env * level
                    }
                }
            }
            b.reverb(wet: 0.45, size: 1.3)
            return [b.finished(peak: 0.7)]

        case .footstep:
            var b = SynthBuffer(seconds: 0.12)
            b.lowNoise(at: 0, length: 0.1, seed: 151, amp: 1, cutoff: { _ in 650 }, envelope: { ad($0, attack: 0.004, decay: 0.03) })
            b.noise(at: 0.002, length: 0.04, seed: 152, amp: 0.3, cutoff: { _ in 2400 }, envelope: { exp(-$0 / 0.01) })
            return variants(b.finished(peak: 0.5), [0.85, 0.95, 1.05, 1.15])

        case .skillLearn:
            var b = SynthBuffer(seconds: 2.2)
            for index in 0..<10 {
                let freq = 880 * pow(4, Double(index) / 9)
                b.bell(at: Double(index) * 0.045, freq: freq, amp: 0.22, decay: 0.35)
            }
            for freq in [523.3, 659.3, 784.0, 987.8] {
                b.add(at: 0.3, length: 1.4) { t in
                    sin(2 * .pi * freq * t) * ad(t, attack: 0.15, decay: 0.5) * 0.12
                }
            }
            b.reverb(wet: 0.45, size: 1.2)
            return [b.finished(peak: 0.7)]

        case .campfire:
            // A seamless 5s loop: soft low rumble + scattered crackles, crossfaded end→start.
            let loop = 5.0, overlap = 0.4
            var b = SynthBuffer(seconds: loop + overlap)
            b.lowNoise(at: 0, length: loop + overlap, seed: 161, amp: 0.5,
                       cutoff: { 220 + 80 * sin(2 * .pi * 0.3 * $0) },
                       envelope: { 0.75 + 0.25 * sin(2 * .pi * 0.7 * $0) })
            b.crackle(at: 0, length: loop + overlap, perSecond: 9, seed: 162, amp: 0.55)
            b.crackle(at: 0, length: loop + overlap, perSecond: 2, seed: 163, amp: 1.0)
            let n = Int(loop * SynthBuffer.rate), fade = Int(overlap * SynthBuffer.rate)
            var looped = Array(b.samples[0..<n])
            for i in 0..<fade {
                let k = Double(i) / Double(fade)
                looped[i] = looped[i] * k + b.samples[n + i] * (1 - k)
            }
            b.samples = looped
            let peakValue = looped.map(abs).max() ?? 1
            return [looped.map { Float($0 / peakValue * 0.5) }]
        }
    }

    private static func variants(_ base: [Float], _ ratios: [Double]) -> [[Float]] {
        ratios.map { $0 == 1 ? base : SynthBuffer.resample(base, ratio: $0) }
    }
}
