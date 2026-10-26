import Foundation

// MARK: - Monster decisions (game.md §7.3)
//
// Pure functions over the fight's state: which skill a monster plays next and who it lands on.
// Nothing here is random (every random number comes from the dice, game.md §8), so the nameplate's
// next-move icon is exactly what the monster will do if nothing changes before its charge fills.

/// What a monster will do when its charge fills.
struct EnemyPlan: Hashable {
    var skill: EnemySkillDef
    /// The rule that picked it; nil = the pattern's next move.
    var ruleIndex: Int?
}

enum EnemyBrain {
    /// Rules first, in order (first one whose conditions hold, that isn't cooling down or used
    /// up); otherwise the pattern's next move.
    static func plan(for enemy: EnemyInstance, enemies: [EnemyInstance], heroes: [HeroState]) -> EnemyPlan? {
        for (index, rule) in enemy.def.allRules.enumerated() {
            guard let skill = enemy.def.skill(id: rule.skill) else { continue }
            if (enemy.ruleCooldowns[index] ?? 0) > 0 { continue }
            if let maxUses = rule.maxUses, (enemy.ruleUses[index] ?? 0) >= maxUses { continue }
            if holds(rule.when, skill: skill, caster: enemy, enemies: enemies, heroes: heroes) {
                return EnemyPlan(skill: skill, ruleIndex: index)
            }
        }
        let pattern = enemy.def.patternSkills
        guard !pattern.isEmpty else { return nil }
        return EnemyPlan(skill: pattern[enemy.moveIndex % pattern.count], ruleIndex: nil)
    }

    static func holds(_ conditions: EnemyRuleConditions?, skill: EnemySkillDef, caster: EnemyInstance,
                      enemies: [EnemyInstance], heroes: [HeroState]) -> Bool {
        guard let conditions else { return true }
        let livingEnemies = enemies.filter(\.isAlive)
        let livingHeroes = heroes.filter(\.isAlive)
        if let share = conditions.selfHPBelow, !(caster.hpShare < share) { return false }
        if let share = conditions.allyHPBelow, !livingEnemies.contains(where: { $0.hpShare < share }) { return false }
        if let share = conditions.heroHPBelow, !livingHeroes.contains(where: { $0.hpShare < share }) { return false }
        if let count = conditions.minAlliesAlive, livingEnemies.count < count { return false }
        if let count = conditions.maxAlliesAlive, livingEnemies.count > count { return false }
        if conditions.unlessActive == true,
           !wouldAddSomething(skill, caster: caster, enemies: enemies, heroes: heroes) { return false }
        return true
    }

    /// Whether some target of the skill lacks one of its timed effects (a skill without timed
    /// effects always counts as adding something).
    static func wouldAddSomething(_ skill: EnemySkillDef, caster: EnemyInstance,
                                  enemies: [EnemyInstance], heroes: [HeroState]) -> Bool {
        let timed = skill.effects.filter { !$0.type.rolls }
        guard !timed.isEmpty else { return true }
        for effect in timed {
            let target = skill.target(of: effect)
            if effect.type.hitsHeroes {
                for index in heroTargets(target, heroes: heroes) {
                    let hero = heroes[index]
                    switch effect.type {
                    case .stun: if !hero.isStunned { return true }
                    case .weaken: if hero.weakens.isEmpty { return true }
                    case .vulnerable: if hero.vulnerables.isEmpty { return true }
                    default: return true
                    }
                }
            } else {
                for index in enemyTargets(target, caster: caster, enemies: enemies) {
                    let enemy = enemies[index]
                    switch effect.type {
                    case .armor: if !enemy.hasArmor { return true }
                    case .damageBuff: if enemy.damageBuffs.isEmpty { return true }
                    default: return true
                    }
                }
            }
        }
        return false
    }

    // MARK: Targets

    /// Living heroes a hero-side target means: all of them, or the most hurt one (lowest share of
    /// max HP, ties → party order).
    static func heroTargets(_ target: EnemySkillTarget, heroes: [HeroState]) -> [Int] {
        let living = heroes.indices.filter { heroes[$0].isAlive }
        switch target {
        case .heroes:
            return living
        case .hero:
            return mostHurt(living) { heroes[$0].hpShare }.map { [$0] } ?? []
        case .selfEnemy, .ally, .allies:
            return []
        }
    }

    /// Living monsters a monster-side target means: itself, the most hurt (itself included, ties →
    /// roster order), or all of them.
    static func enemyTargets(_ target: EnemySkillTarget, caster: EnemyInstance, enemies: [EnemyInstance]) -> [Int] {
        let living = enemies.indices.filter { enemies[$0].isAlive }
        switch target {
        case .selfEnemy:
            return living.filter { enemies[$0].id == caster.id }
        case .ally:
            return mostHurt(living) { enemies[$0].hpShare }.map { [$0] } ?? []
        case .allies:
            return living
        case .heroes, .hero:
            return []
        }
    }

    private static func mostHurt(_ indices: [Int], share: (Int) -> Double) -> Int? {
        indices.reduce(nil as Int?) { best, index in
            guard let best else { return index }
            return share(index) < share(best) ? index : best
        }
    }
}

extension HeroState {
    var hpShare: Double { Double(hp) / Double(max(1, maxHP)) }
}
