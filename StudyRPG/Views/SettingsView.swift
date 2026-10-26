import SwiftUI

// MARK: - Settings (game.md §2)

/// The settings gear used on every screen that has no other way to reach Settings (game.md §2):
/// owns its own sheet, so dropping it into any toolbar or bar is enough.
struct SettingsGearButton: View {
    /// Round gold-rimmed chip over scenery; `nil` = a plain toolbar button (system styling).
    var chipSize: CGFloat? = 34
    @State private var showSettings = false

    var body: some View {
        let button = Button {
            Sound.play(.tap)
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showSettings) { SettingsView() }

        if let chipSize {
            button.buttonStyle(ChromeIconButtonStyle(size: chipSize))
        } else {
            button
        }
    }
}

/// Presentation-only preferences, laid out for landscape: a title, then two parchment cards side
/// by side (Combat & learning | Sound & feel). Scrolls only if the text size is very large.
struct SettingsView: View {
    @Environment(GameSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// Macs have no silent switch (game.md §15).
    private var soundDetail: LocalizedStringKey {
        #if os(iOS)
        "Button clicks (other sounds are off for now). Follows the silent switch."
        #else
        "Button clicks (other sounds are off for now)."
        #endif
    }

    var body: some View {
        // Mac: just big enough for the two cards, not a mostly empty panel.
        sheetContent.gameSheetFrame(fitting: CGSize(width: 880, height: 540))
    }

    @ViewBuilder private var sheetContent: some View {
        @Bindable var settings = settings
        ZStack(alignment: .topTrailing) {
            DeskBackground()

            ScrollView {
                VStack(spacing: 16) {
                    ScreenTitle(title: "Settings", size: 26)
                        .padding(.top, 6)

                    HStack(alignment: .top, spacing: 14) {
                        SettingsCard(title: "Combat & Learning", icon: "graduationcap.fill") {
                            SettingsToggleRow(
                                icon: settings.fastMode ? "hare.fill" : "tortoise.fill",
                                tint: Palette.strength,
                                title: "Fast mode",
                                detail: "Shorter pauses, faster dice, and an enemy's attack on both heroes is thrown at once.",
                                isOn: $settings.fastMode
                            )
                            SettingsDivider()
                            SettingsToggleRow(
                                icon: "hand.raised.fill",
                                tint: Palette.damage,
                                title: "Pause on wrong answers",
                                detail: "Keep the right answer and its explanation on screen until you tap Continue.",
                                isOn: $settings.waitAfterWrongAnswer
                            )
                            SettingsDivider()
                            SettingsToggleRow(
                                icon: "checkmark.seal.fill",
                                tint: Palette.health,
                                title: "Pause on right answers",
                                detail: "Off: a right answer moves on immediately.",
                                isOn: $settings.waitAfterRightAnswer
                            )
                        }

                        SettingsCard(title: "Sound & Feel", icon: "speaker.wave.2.fill") {
                            SettingsToggleRow(
                                icon: settings.soundEffects ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                tint: Palette.mana,
                                title: "Sound effects",
                                detail: soundDetail,
                                isOn: $settings.soundEffects
                            )
                            VolumeSliderRow(volume: $settings.soundVolume)
                                .disabled(!settings.soundEffects)
                                .opacity(settings.soundEffects ? 1 : 0.45)
                            #if os(iOS)
                            // Macs have no haptics (game.md §15).
                            SettingsDivider()
                            SettingsToggleRow(
                                icon: "hand.tap.fill",
                                tint: Palette.control,
                                title: "Haptics",
                                detail: "A tap you can feel on heavy hits and explosions.",
                                isOn: $settings.haptics
                            )
                            #endif
                        }
                    }
                    .frame(maxWidth: 820)

                    LanguageRow(language: $settings.language)
                        .frame(maxWidth: 820)

                    Text("Settings only change how the game looks, sounds and paces itself — never its balance.")
                        .font(.serif(11))
                        .italic()
                        .foregroundStyle(Palette.text.opacity(0.75))
                        .shadow(color: .black, radius: 3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                Sound.play(.tap)
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(ChromeIconButtonStyle())
            .accessibilityLabel("Close")
            .macKeyboardShortcut(.cancelAction)
            .padding(.top, 8)
            .padding(.trailing, 20)
        }
        .tint(Palette.gold)
    }
}

/// One parchment card with a small gilded heading.
private struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.serif(12, .bold))
                    .textCase(.uppercase)
                    .tracking(0.9)
            }
            .foregroundStyle(Palette.ink.opacity(0.6))
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .parchment(padding: 16)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.ink.opacity(0.12))
            .frame(height: 1)
    }
}

/// Medallion icon, title + one-line explanation, and a toggle.
private struct SettingsToggleRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .center, spacing: 11) {
                SettingsMedallion(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.readable(15, .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.readable(11))
                        .foregroundStyle(Palette.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // A switch on every platform (Mac would otherwise draw a checkbox).
        .toggleStyle(.switch)
        .tint(Palette.gold)
        .onChange(of: isOn) { _, _ in Sound.play(.tap) }
    }
}

/// The icon in a dark ink medallion, so the semantic colors stay vivid on parchment.
private struct SettingsMedallion: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Palette.ink.opacity(0.88)))
            .overlay(Circle().strokeBorder(Palette.gold.opacity(0.55), lineWidth: 1))
    }
}

/// The in-game language (game.md §2 Language): System, then each language in its own name.
/// Switches at once; system-provided text (photo picker, standard menus) follows on the next launch.
private struct LanguageRow: View {
    @Binding var language: AppLanguage

    private func label(_ language: AppLanguage) -> String {
        switch language {
        case .system: L("System")
        // Each language is named in itself, so it can be found from any language.
        case .english, .german: Locale(identifier: language.rawValue).localizedString(forLanguageCode: language.rawValue)?.localizedCapitalized ?? language.rawValue
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            SettingsMedallion(icon: "globe", tint: Palette.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Language")
                    .font(.readable(15, .semibold))
                    .foregroundStyle(Palette.ink)
                Text("System follows your device's language.")
                    .font(.readable(11))
                    .foregroundStyle(Palette.ink.opacity(0.62))
            }
            Spacer(minLength: 12)
            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: label(language)).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .onChange(of: language) { _, _ in Sound.play(.tap) }
        }
        .parchment(padding: 14)
    }
}

/// Effects volume; plays a sample coin when you let go so you hear the new level.
private struct VolumeSliderRow: View {
    @Binding var volume: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .frame(width: 32)
            Slider(value: $volume, in: 0...1) { editing in
                if !editing { Sound.play(.tap) }
            }
            .accessibilityLabel("Effects volume")
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.55))
            Text("\(Int((volume * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.7))
                .frame(width: 38, alignment: .trailing)
        }
    }
}
