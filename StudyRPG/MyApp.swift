import SwiftUI

@main struct MyApp: App {
    @State private var deckStore = DeckStore()
    @State private var statsStore = CardStatsStore()
    @State private var settings = GameSettings()
    /// The Mac Game menu's link to the main menu (game.md §15).
    @State private var menuRouter = GameMenuRouter()

    init() {
        #if os(macOS)
        // Art is cached sharp enough for the biggest canvas any attached screen can show
        // (game.md §15, §17). A bigger screen plugged in later just shows slightly softer art.
        ArtCache.canvasUpscale = NSScreen.screens
            .map { CanvasFit.fit(in: $0.frame.size, pillarbox: true, scalesUp: true).scale }
            .max() ?? 1
        #endif
    }

    #if os(macOS)
    private let frameRateHUDAlignment = Alignment.bottomTrailing
    #else
    private let frameRateHUDAlignment = Alignment.bottom
    #endif

    var body: some Scene {
        WindowGroup {
            WidescreenCanvas {
                ContentView()
                    .environment(deckStore)
                    .environment(statsStore)
                    .environment(settings)
                    .environment(menuRouter)
                    .gameLocale()
                    #if DEBUG
                    // Bottom center, in the home-indicator strip: the top-left corner holds the
                    // map's abandon flag and the fight's back button. Mac has no such strip, so
                    // the bottom-right corner, clear of the fight console's middle.
                    .overlay(alignment: frameRateHUDAlignment) {
                        FrameRateHUD()
                            .allowsHitTesting(false)
                            .padding(.bottom, 2)
                            .ignoresSafeArea(.container, edges: .bottom)
                    }
                    #endif
            }
            .background(Palette.night)
            #if os(macOS)
            // Freely resizable, at least 960×540 (game.md §15).
            .frame(minWidth: 960, minHeight: 540)
            // The title bar matches the game: dark, and see-through to the night background
            // instead of a bright system bar.
            .preferredColorScheme(.dark)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
            .task {
                // Synthesizes every sound effect on a background queue (game.md §19).
                SoundEngine.shared.prepare(enabled: settings.soundEffects, volume: settings.soundVolume)
            }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
        .commands { GameMenuCommands(router: menuRouter) }
        #endif

        #if os(macOS)
        // Settings… (⌘,) in the app menu: the same settings as the in-game gear (game.md §2).
        Settings {
            SettingsView()
                .environment(settings)
                .gameLocale()
        }
        #endif
    }
}
