import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Theme (fantasy / paper / moody / muted)
//
// Adapted from an earlier prototype's Theme.swift, which already nailed this exact look — a
// muted twilight palette, warm parchment cards, serif type, thin gold rules. All current sprite
// art (hero/enemy PNGs copied into Assets.xcassets, and every SF Symbol placeholder below) is
// provisional — the user intends to replace all of it with hand-drawn art eventually. Keep
// placeholders theme-consistent, not "finished."

/// A calm, muted twilight palette: night sky, parchment, soft gold and gentle accents.
enum Palette {
    static let night = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let dusk = Color(red: 0.13, green: 0.16, blue: 0.23)
    static let horizon = Color(red: 0.33, green: 0.31, blue: 0.40)
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.17)

    static let parchment = Color(red: 0.91, green: 0.87, blue: 0.78)
    static let parchmentShade = Color(red: 0.78, green: 0.71, blue: 0.58)
    static let ink = Color(red: 0.19, green: 0.16, blue: 0.13)

    static let gold = Color(red: 0.80, green: 0.68, blue: 0.45)
    static let moss = Color(red: 0.55, green: 0.67, blue: 0.50)
    static let mist = Color(red: 0.56, green: 0.68, blue: 0.82)
    static let steel = Color(red: 0.50, green: 0.61, blue: 0.76)
    static let ember = Color(red: 0.82, green: 0.50, blue: 0.37)
    static let glow = Color(red: 0.98, green: 0.78, blue: 0.48)

    static let text = Color(red: 0.93, green: 0.90, blue: 0.84)
    static let textDim = Color(red: 0.93, green: 0.90, blue: 0.84).opacity(0.6)
}

extension Font {
    /// Serif typeface used throughout for a storybook feel.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Serif that follows the player's text-size setting (capped at 1.5× so landscape layouts
    /// hold). Used for reading content: flashcards, decks, sheets. The fight HUD stays fixed.
    /// Mac has no system text size: fixed there.
    static func readable(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        #if os(iOS)
        let scaled = min(size * 1.5, UIFontMetrics(forTextStyle: .body).scaledValue(for: size))
        #else
        let scaled = size
        #endif
        return .system(size: scaled, weight: weight, design: .serif)
    }
}

/// One aggregated buff/debuff on a character. Displayed as icon + total magnitude, with an
/// hourglass and remaining rounds when timed. Sources/names live in the info sheet, not here.
struct StatusEffect: Identifiable {
    var id: String
    /// Effects of the same kind are summed into one badge on the battlefield.
    var kind: String
    var icon: String
    var value: Int?
    var duration: Int?
    var tint: Color
    var name: String
    var source: String
    var detail: String
}

/// Compact, text-light effect badge: `[icon] value [hourglass] rounds`.
struct EffectBadge: View {
    let icon: String
    var value: Int? = nil
    var duration: Int? = nil
    var tint: Color = Palette.gold

    var body: some View {
        badgeContent
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 0.8))
            .fixedSize()
    }

    private var badgeContent: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            if let value {
                Text("\(value)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            if let duration {
                Image(systemName: "hourglass")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.text.opacity(0.85))
                Text("\(duration)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

/// A character's effect row, shown under its sprite. Effects of the same kind are summed by the
/// caller, so e.g. two bonus-die sources appear as one `[die] 2` badge.
struct StatusEffectRow: View {
    let effects: [StatusEffect]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(effects) { effect in
                EffectBadge(icon: effect.icon, value: effect.value, duration: effect.duration, tint: effect.tint)
            }
        }
    }
}

/// A small gilded capsule used for form/list section headers, so headings stay readable over the
/// scenery instead of inheriting the system's dark-on-dark secondary label color.
struct SectionHeaderLabel: View {
    let text: Text

    init(_ text: LocalizedStringKey) {
        self.text = Text(text)
    }

    init(text: LocalizedStringKey) {
        self.text = Text(text)
    }

    /// Already-localized text (built with `L`), shown as is. Disfavored so literals still localize.
    @_disfavoredOverload
    init(text: String) {
        self.text = Text(verbatim: text)
    }

    var body: some View {
        HStack(spacing: 0) {
            text
                .font(.serif(11, .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Palette.goldGlow)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.night.opacity(0.75)))
                .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.3), lineWidth: 0.8))
            Spacer(minLength: 0)
        }
    }
}

/// A thin gold rule with a diamond in the middle — the storybook divider under titles.
struct OrnamentDivider: View {
    var width: CGFloat = 180
    var color: Color = Palette.gold

    var body: some View {
        HStack(spacing: 6) {
            LinearGradient(colors: [color.opacity(0), color.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            Diamond()
                .fill(color)
                .frame(width: 7, height: 9)
            LinearGradient(colors: [color.opacity(0.8), color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

/// Big serif screen title with a gilded glow and an ornament underneath (menus, settings).
struct ScreenTitle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var size: CGFloat = 30

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.serif(size, .bold))
                .foregroundStyle(
                    LinearGradient(colors: [Palette.goldGlow, Palette.gold], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.8), radius: 6, y: 2)
                .shadow(color: Palette.gold.opacity(0.35), radius: 14)
            OrnamentDivider(width: size * 6)
            if let subtitle {
                Text(subtitle)
                    .font(.serif(12, .semibold))
                    .italic()
                    .foregroundStyle(Palette.text.opacity(0.8))
                    .shadow(color: .black.opacity(0.8), radius: 4)
            }
        }
    }
}

/// Round dark chip with a gold rim for icon-only buttons floating over scenery (close, settings).
struct ChromeIconButtonStyle: ButtonStyle {
    var size: CGFloat = 38
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.37, weight: .bold))
            .foregroundStyle(Palette.goldGlow)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.black.opacity(configuration.isPressed ? 0.8 : 0.6)))
            .overlay(Circle().strokeBorder(Palette.gold.opacity(0.6), lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .hoverHighlight(isEnabled, amount: 0.12)
    }
}

/// Dark translucent panel with a fine double gold rule — for HUD-style chrome over the scenery.
struct PanelModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.panel.opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.gold.opacity(0.12), lineWidth: 1).padding(4))
    }
}

/// Warm parchment card with ink-colored text — for readable content (forms, flashcards, dialogs).
struct ParchmentModifier: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .foregroundStyle(Palette.ink)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(RadialGradient(colors: [Palette.parchment, Palette.parchmentShade], center: .center, startRadius: 60, endRadius: 700))
            )
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1).padding(5))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

/// Lighter parchment treatment for list/form rows — no shadow, so rows don't look like floating cards.
struct ParchmentRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .foregroundStyle(Palette.ink)
            // Fully opaque: translucent rows let bright mountain bands read as stains across the card.
            .background(Palette.parchment)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.ink.opacity(0.15), lineWidth: 1))
    }
}

extension View {
    func panel(padding: CGFloat = 16) -> some View { modifier(PanelModifier(padding: padding)) }
    func parchment(padding: CGFloat = 20) -> some View { modifier(ParchmentModifier(padding: padding)) }
    func parchmentRow() -> some View { modifier(ParchmentRowModifier()) }
    /// Transparent list/form rows on the study desk — the standard way every list screen in this
    /// app shows readable parchment rows on the candlelit table (game.md §17).
    func deskList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(DeskBackground())
    }
    /// No visible navigation bar anywhere (user request 2026-10-18): no bar background and no
    /// title, only the bar's buttons floating over the scenery, in light chrome. Always inline, so
    /// the top area has the same height on every screen (a large title made it jump).
    /// Forced visible: the main menu's bar is empty, so the system dropped it there, and every
    /// pushed screen shifted down once its back-button bar settled in after the transition.
    /// Every such screen also gets the settings gear (Settings are always reachable, game.md §2);
    /// pass `settings: false` where the screen shows its own.
    func themedNavigationBar(settings: Bool = true) -> some View {
        #if os(iOS)
        self
            .toolbar {
                if settings {
                    ToolbarItem(placement: .topBarTrailing) { SettingsGearButton(chipSize: nil) }
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #else
        // Mac keeps the standard window title bar (game.md §15); the gear sits in its toolbar.
        self
            .toolbar {
                if settings {
                    ToolbarItem(placement: .primaryAction) { SettingsGearButton(chipSize: nil) }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .modifier(EscapeGoesBack())
        #endif
    }
    /// Slow, subtle breathing so standing sprites never look pasted-on.
    func idleBreathing(_ amount: CGFloat = 0.012) -> some View {
        modifier(IdleBreathing(amount: amount))
    }
}

struct IdleBreathing: ViewModifier {
    var amount: CGFloat = 0.012
    @State private var expanded = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(expanded ? 1 + amount : 1, anchor: .bottom)
            .onAppear {
                // No perpetual animation at all when breathing is off (saves a constant redraw).
                guard amount > 0 else { return }
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                    expanded = true
                }
            }
    }
}

struct QuestButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .primary
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.serif(kind == .quiet ? 14 : 16, .semibold))
            .padding(.horizontal, kind == .quiet ? 12 : 20)
            .padding(.vertical, kind == .quiet ? 7 : 10)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill(pressed: configuration.isPressed)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Sound.play(.tap) }
            }
            .hoverHighlight(isEnabled)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Palette.ink
        // `.secondary` buttons are used inside parchment cards, so they need ink-colored text;
        // cream-on-parchment was effectively invisible.
        case .secondary: return Palette.ink.opacity(0.9)
        // Nav-bar buttons over the dark scenery: full cream, never dimmed (dim read as disabled).
        case .quiet: return Palette.text
        }
    }
    private var border: Color {
        switch kind {
        case .primary: return Palette.glow.opacity(0.6)
        case .secondary: return Palette.ink.opacity(0.35)
        case .quiet: return .clear
        }
    }
    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .primary: return pressed ? Palette.gold.opacity(0.85) : Palette.gold
        case .secondary: return Palette.gold.opacity(pressed ? 0.35 : 0.18)
        case .quiet: return Color.white.opacity(pressed ? 0.08 : 0.0)
        }
    }
}



// MARK: - Extra Combat Palette Colors
extension Palette {
    static let goldGlow = Color(red: 1.0, green: 0.85, blue: 0.45)
    static let crimson = Color(red: 0.78, green: 0.22, blue: 0.20)
    static let nightSky = Color(red: 0.08, green: 0.10, blue: 0.16)
    static let groundDark = Color(red: 0.06, green: 0.07, blue: 0.09)

    // Dice (game.md §8): parchment bone for heroes, blood-red for enemies.
    static let dieBone = Color(red: 0.96, green: 0.92, blue: 0.84)
    static let dieBoneShade = Color(red: 0.76, green: 0.68, blue: 0.54)
    static let dieBlood = Color(red: 0.60, green: 0.19, blue: 0.16)
    static let dieBloodShade = Color(red: 0.30, green: 0.07, blue: 0.07)

    // Semantic combat colors (game.md §17): every number/icon on the fight screen is colored by
    // what it means, so the battlefield reads without words.
    static let damage = Color(red: 0.88, green: 0.32, blue: 0.28)
    static let health = Color(red: 0.47, green: 0.78, blue: 0.43)
    static let mana = Color(red: 0.42, green: 0.64, blue: 0.97)
    static let strength = Color(red: 1.0, green: 0.82, blue: 0.30)
    static let block = Color(red: 0.82, green: 0.86, blue: 0.92)
    /// Crowd control and debuffs on enemies: stun, weaken, vulnerable.
    static let control = Color(red: 0.74, green: 0.56, blue: 0.98)

    static func combatColor(_ kind: CombatLogEntry.Kind) -> Color {
        switch kind {
        case .damage, .wrong: return damage
        case .heal, .correct: return health
        case .mana: return mana
        case .strength, .buff: return strength
        case .block, .armor: return block
        case .stun, .debuff: return control
        }
    }
}

enum SpriteKind {
    case hero, enemy, consumable, relic

    var assetPrefix: String {
        switch self {
        case .hero: return "hero_"
        case .enemy: return "enemy_"
        case .consumable, .relic: return "item_"
        }
    }
    var placeholderSymbol: String {
        switch self {
        case .hero: return "person.fill"
        case .enemy: return "pawprint.fill"
        case .consumable: return "flask.fill"
        case .relic: return "seal.fill"
        }
    }
}

struct SpriteView: View {
    var spriteId: String
    var kind: SpriteKind
    var size: CGFloat = 64
    var targetHeight: CGFloat? = nil
    /// Subtle idle breathing — only the world map's walking party uses it; every other scene is
    /// static (game.md §17), so it's off by default.
    var breathes: Bool = false

    var body: some View {
        let assetName = "\(kind.assetPrefix)\(spriteId)"
        let desiredHeight = targetHeight ?? size
        if let uiImage = ArtCache.thumbnail(assetName, height: desiredHeight) {
            if let targetHeight {
                Image(platformImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: targetHeight)
                    .idleBreathing(breathes ? 0.012 : 0)
            } else {
                Image(platformImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        } else {
            // Procedural art is drawn square; using `size` for both dimensions keeps circles
            // circular when a battle figure provides only a target height.
            let side = targetHeight ?? size
            if ProceduralSpriteArt.hasArt(for: spriteId) {
                ProceduralSpriteArt(spriteId: spriteId)
                    .frame(width: side, height: side)
                    .idleBreathing(breathes ? 0.012 : 0)
            } else {
                proceduralFallback
                    .frame(width: side, height: side)
            }
        }
    }

    @ViewBuilder
    private var proceduralFallback: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.parchment, Palette.parchmentShade], center: .center, startRadius: 4, endRadius: size))
                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.4), lineWidth: 1.5))
            Image(systemName: kind.placeholderSymbol)
                .font(.system(size: size * 0.4))
                .foregroundStyle(Palette.ink.opacity(0.7))
        }
    }
}

#if os(macOS)
/// Mac: Esc goes back from a pushed screen or closes a sheet (game.md §15). Only on presented
/// screens — on the main menu `dismiss` would close the window.
private struct EscapeGoesBack: ViewModifier {
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.background {
            if isPresented {
                Button("Back") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
#endif
