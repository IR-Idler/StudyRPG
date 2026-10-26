import SwiftUI

// MARK: - Xcode previews of the run's scenes
//
// Previews only (never shown in the game): a fresh run with the bundled starter decks, opened
// straight on the first shop / campfire / event of its map, so the scenes can be checked
// without playing through a run. Previews run in their own sandbox, not the player's data.

#if DEBUG
@MainActor
private enum PreviewRun {
    static func make() -> (RunState, GameContent)? {
        guard let content = try? ContentLoader.load() else { return nil }
        let heroes = Array(content.classes.prefix(2))
        let run = RunState(content: content, heroClasses: heroes, decks: content.starterDecks, statsStore: CardStatsStore())
        return (run, content)
    }

    static func node(_ type: MapNodeType, in run: RunState) -> Int? {
        run.map.nodes.first { $0.type == type }?.id
    }
}

#Preview("Shop", traits: .landscapeLeft) {
    if let (run, _) = PreviewRun.make(), let id = PreviewRun.node(.shop, in: run) {
        ShopView(run: run, nodeID: id, onLeave: {})
            .environment(GameSettings())
    }
}

#Preview("Campfire", traits: .landscapeLeft) {
    if let (run, _) = PreviewRun.make(), let id = PreviewRun.node(.campfire, in: run) {
        CampfireView(run: run, nodeID: id, onDone: {})
            .environment(GameSettings())
    }
}

#Preview("Event", traits: .landscapeLeft) {
    if let (run, _) = PreviewRun.make(), let id = PreviewRun.node(.event, in: run) {
        EventView(run: run, nodeID: id, onDone: {})
            .environment(GameSettings())
    }
}

#Preview("Skill reward", traits: .landscapeLeft) {
    if let (run, _) = PreviewRun.make() {
        let offer = SkillOffer(choices: Dictionary(uniqueKeysWithValues: run.heroes.map { ($0.id, $0.classDef.skills.suffix(3).map(\.id)) }))
        SkillRewardView(run: run, offer: offer)
            .environment(GameSettings())
    }
}
#Preview("Item art", traits: .landscapeLeft) {
    let ids = ItemArt.supported.sorted()
    ZStack {
        Palette.panel.ignoresSafeArea()
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(92)), count: 8), spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    VStack(spacing: 2) {
                        ItemArtView(spriteId: id).frame(width: 80, height: 80)
                        Text(id).font(.system(size: 8)).foregroundStyle(Palette.textDim)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { ItemArtView(spriteId: $0).frame(width: 24, height: 24) }
            }
        }
    }
}
#Preview("Skill art", traits: .landscapeLeft) {
    if let content = try? ContentLoader.load() {
        let skills = content.classes.flatMap(\.skills)
        ZStack {
            Palette.panel.ignoresSafeArea()
            VStack(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84)), count: 11), spacing: 8) {
                    ForEach(skills) { skill in
                        VStack(spacing: 3) {
                            SkillIcon(skill: skill, size: 64)
                            Text(skill.name).font(.system(size: 8)).foregroundStyle(Palette.textDim).lineLimit(1)
                        }
                    }
                }
                // Fight-console size.
                HStack(spacing: 5) {
                    ForEach(skills) { SkillIcon(skill: $0, size: 28) }
                }
            }
        }
    }
}
#Preview("Event art", traits: .landscapeLeft) {
    ZStack {
        SceneryBackground()
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(170)), count: 4), spacing: 6) {
            ForEach(EventScene.allCases, id: \.self) { scene in
                VStack(spacing: 0) {
                    EventScenePlaceholder(scene: scene).frame(width: 150, height: 150)
                    Text(scene.rawValue).font(.system(size: 9)).foregroundStyle(Palette.textDim)
                }
            }
        }
    }
}
#endif
