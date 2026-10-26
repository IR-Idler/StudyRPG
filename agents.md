# Agent Instructions — Study RPG

Rules for anyone working in this repo. Game behavior: `game.md` (index + decisions) → `docs/*.md`. Backstory: `HISTORY.md` (open only when needed).

## Rules

- **Docs are the source of truth.** Before a change, read the relevant § (find it in the `game.md` index). In the same change, update the doc: numbers in JSON ↔ tables, mechanics ↔ prose, moved files ↔ index. Don't contradict a decision listed in `game.md` without asking.
- **All player-facing text is localized** (§13 "Localization"): UI text as `Text("…")`-style literals or `L("…")` for `String`s built in code, never a bare English `String` shown with `Text(verbatim)`. **German is on hold (user decision 2026-10-27): write English only, don't add German** to `Localizable.xcstrings` or `Content/Content.xcstrings` — the translations get caught up in one later pass (the German-coverage test in `LocalizationTests` is disabled until then).
- **No game content in Swift.** Enemies, items, relics, classes, skills, encounters, prices and all balance numbers live in `StudyRPG/Content/*.json`; Swift interprets them generically (no `switch` on an id). Malformed content must fail loudly in `ContentLoader`, naming file and field. Schemas: §13.
- **Code layout:** Create new files with `XcodeWrite` (registers them); prefer a new file over growing one past ~1000 lines. Don't edit `project.pbxproj`; don't use `XcodeNewTarget` (ask the user).
- **Swift:** SwiftUI, `@Observable`, `async`/`await`, no Combine. One target, three platforms: never use UIKit/AppKit types directly — go through `Views/Platform.swift` (`PlatformImage`, `PlatformGraphics.image`, `Image(platformImage:)`…) or `#if os(iOS)` for features Mac doesn't have (§15). Use `.buttonStyle(.gamePlain)`, not `.plain` (Mac hover). Visuals only via `Views/Theme.swift` (`Palette`, `.panel()`, `.parchment()`, `QuestButtonStyle`…); art only via `ArtCache`; sprite naming and asset table in §17.
- **Tests:** Swift Testing in `StudyRPGTests` (one file per system). Every suite calls `Fixtures.isolateUserData()`; all user data goes through `UserDataLocation`. Tests read the real JSON and pick things by behavior, never by id or number. Run `RunAllTests` after changing `Models/`, `Services/` or `Content/`; add/update a test with every rule change.
- **Verification is the user's:** build + test, then ask the user whether it's okay before continuing. Never judge visuals yourself — no screenshot/preview rounds unless asked. Never build/run on the user's iPhone (simulator or My Mac only). After a platform-touching change, build and test on both iOS Simulator and My Mac.
- iPhone + iPad (landscape only) and native Mac — not Catalyst (§15). `resource/` is the user's raw art dump — don't delete it. `resource/`, docs and `HISTORY.md` are not target members; only `Content/*.json` and `Assets.xcassets` ship.

## Status

- Everything marked **[Built]** in the docs is implemented and tested (2026-10-26). Not tested: looks, sounds, dice animation.
- Not built: mid-fight save, a third act, boss relics, ascension, §18. Act II has only one enemy type and reuses Act I scenes/events (user decision). §14 Monte Carlo predates magic damage and monster rules.
- Mac (§15) is built. Open: the project-setting items under §15 "Open items before release" (app icon name, Requires Full Screen).
- Known minor bug: in the card editor, taps in the top ~80 pt of the scrolled form can be swallowed.
