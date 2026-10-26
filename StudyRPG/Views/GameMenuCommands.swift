import SwiftUI

// MARK: - Mac menu bar (game.md §15)

/// What the Mac menu bar's Game menu can do right now, and what was picked. The main menu
/// (`ContentView`) keeps the flags current and handles the picks; iOS never sets `pending`.
@Observable
final class GameMenuRouter {
    enum Action: Equatable { case newRun, continueRun, decks }

    /// Only true while the main menu is on screen with no run open, so a command never stacks a
    /// screen on top of another one.
    var canStartRun = false
    var canContinue = false
    var canOpenDecks = false
    /// The last picked command; the main menu handles it and clears it.
    var pending: Action?
}

#if os(macOS)
/// The "Game" menu (New Run ⌘N, Continue, Decks). Settings… ⌘, comes from the Settings scene.
/// Titles go through `L` because the menu bar sits outside the views' `\.locale` (game.md §2 Language).
struct GameMenuCommands: Commands {
    let router: GameMenuRouter

    var body: some Commands {
        // One game window: no File › New Window, so ⌘N is New Run.
        CommandGroup(replacing: .newItem) {}
        CommandMenu(L("Game")) {
            Button(L("New Run")) { router.pending = .newRun }
                .keyboardShortcut("n")
                .disabled(!router.canStartRun)
            Button(L("Continue")) { router.pending = .continueRun }
                .disabled(!router.canContinue)
            Divider()
            Button(L("Decks")) { router.pending = .decks }
                .disabled(!router.canOpenDecks)
        }
    }
}
#endif
