import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - Shop (game.md §10)

struct ShopView: View {
    @Bindable var run: RunState
    let nodeID: Int
    var onLeave: () -> Void

    @State private var quizCard: PresentedCard?

    private var shop: ShopConfig { run.content.balance.shop }
    /// nil = not haggled yet; true = won (discount), false = lost (surcharge). Saved with the run.
    private var haggleWon: Bool? { run.haggleResult(at: nodeID) }

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()

            VStack(spacing: 0) {
                RunHUD(run: run)

                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    ZStack {
                        // The scenery reaches the screen edges (under the notch); wares and
                        // buttons stay inside the safe area.
                        ArtOrPlaceholder(assetName: "shop_stall", contentMode: .fill) {
                            ShopStallBackdrop()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(edges: [.horizontal, .bottom])

                        // Shopkeeper behind the counter, offering the haggle in a speech bubble.
                        ArtOrPlaceholder(assetName: "shop_keeper") {
                            MerchantPlaceholder()
                        }
                        .frame(width: h * 0.56, height: h * 0.56)
                        .position(x: w * 0.5, y: h * 0.62)

                        haggleBubble
                            .position(x: w * 0.5, y: h * 0.22)

                        ShopCounter()
                            .frame(width: w * 0.36, height: h * 0.20)
                            .position(x: w * 0.5, y: h * 0.91)

                        // Potions on the left shelf, relics on the right.
                        shelf(width: w * 0.32) {
                            ForEach(run.content.items) { item in
                                let price = run.price(item.cost, haggleWon: haggleWon)
                                ShelfWare(price: price, basePrice: item.cost,
                                          canBuy: run.gold >= price && !run.isBagFull, isSold: false,
                                          blockedIcon: run.isBagFull ? "bag.fill" : nil) {
                                    SpriteView(spriteId: item.spriteId, kind: .consumable, size: 40)
                                } effect: {
                                    ItemEffectLabel(effect: item.effect)
                                } onBuy: {
                                    if run.buyPotion(item, at: nodeID) { Sound.play(.purchase) }
                                }
                                .accessibilityLabel(item.name)
                            }
                        }
                        .position(x: w * 0.2, y: h * 0.52)

                        shelf(width: w * 0.28) {
                            let relicStock = run.shopRelics(for: nodeID)
                            if relicStock.isEmpty {
                                Image(systemName: "seal")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Palette.text.opacity(0.3))
                                    .frame(width: 70, height: 80)
                            }
                            ForEach(relicStock) { relic in
                                let price = run.price(relic.cost, haggleWon: haggleWon)
                                let sold = run.isSold(relic.id, at: nodeID)
                                ShelfWare(price: price, basePrice: relic.cost,
                                          canBuy: !sold && run.gold >= price, isSold: sold, blockedIcon: nil) {
                                    SpriteView(spriteId: relic.spriteId, kind: .relic, size: 40)
                                } effect: {
                                    RelicEffectLabel(effect: relic.effect)
                                } onBuy: {
                                    if run.buyRelic(relic, at: nodeID) { Sound.play(.purchase) }
                                }
                                .accessibilityLabel(relic.name)
                            }
                            // One skill scroll per shop: buying it opens a skill offer (game.md §10).
                            let scrollSold = run.isScrollSold(at: nodeID)
                            if scrollSold || run.canLearnSkills {
                                let price = run.price(shop.skillScrollCost, haggleWon: haggleWon)
                                ShelfWare(price: price, basePrice: shop.skillScrollCost,
                                          canBuy: !scrollSold && run.gold >= price && run.pendingSkillOffer == nil,
                                          isSold: scrollSold, blockedIcon: nil) {
                                    Image(systemName: "scroll.fill")
                                        .font(.system(size: 32, weight: .semibold))
                                        .foregroundStyle(Palette.parchment)
                                        .shadow(color: Palette.goldGlow.opacity(0.6), radius: 6)
                                } effect: {
                                    HStack(spacing: 2) {
                                        Image(systemName: "sparkles")
                                        Image(systemName: "plus.circle.fill")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.goldGlow)
                                } onBuy: {
                                    if run.buySkillScroll(at: nodeID) { Sound.play(.purchase) }
                                }
                                .accessibilityLabel("Skill scroll: learn a new skill")
                            }
                        }
                        .position(x: w * 0.8, y: h * 0.33)

                        shelf(width: w * 0.28) {
                            ForEach(run.shopGear(for: nodeID)) { gear in
                                let price = run.price(gear.cost, haggleWon: haggleWon)
                                let sold = run.isSold(gear.id, at: nodeID)
                                ShelfWare(price: price, basePrice: gear.cost,
                                          canBuy: !sold && run.gold >= price, isSold: sold, blockedIcon: nil) {
                                    GearArt(gear: gear, size: 40)
                                } effect: {
                                    GearEffectLabel(gear: gear)
                                } onBuy: {
                                    if run.buyGear(gear, at: nodeID) { Sound.play(.purchase) }
                                }
                                .accessibilityLabel(gear.name)
                            }
                        }
                        .position(x: w * 0.8, y: h * 0.74)

                        Button {
                            run.leave(nodeID)
                            onLeave()
                        } label: {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 54)
                        }
                        .buttonStyle(QuestButtonStyle(kind: .primary))
                        .accessibilityLabel("Leave shop")
                        .position(x: w - 56, y: h - 30)
                    }
                }
            }

            if let quizCard {
                FlashcardQuizHost(card: quizCard, flashcards: run.flashcards) { correct in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        run.recordHaggle(at: nodeID, won: correct)
                        self.quizCard = nil
                    }
                }
            }
        }
        .onAppear { run.enterNode(nodeID) }
    }

    private func shelf<Wares: View>(width: CGFloat, @ViewBuilder wares: () -> Wares) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) { wares() }
            ShopShelf().frame(width: width)
        }
    }

    /// Haggle once per visit: a flashcard decides −25% (right) or +25% (wrong) on everything.
    @ViewBuilder
    private var haggleBubble: some View {
        Group {
            if run.hasHaggled(at: nodeID), let haggleWon {
                HStack(spacing: 6) {
                    Image(systemName: haggleWon ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(haggleWon ? "−\(Int(shop.haggleDiscount * 100))%" : "+\(Int(shop.haggleSurcharge * 100))%")
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(haggleWon ? Palette.health : Palette.damage)
            } else {
                Button {
                    quizCard = run.flashcards.present()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble.fill").foregroundStyle(Palette.ink.opacity(0.8))
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark")
                            Text("−\(Int(shop.haggleDiscount * 100))%")
                        }
                        .foregroundStyle(Color(red: 0.25, green: 0.5, blue: 0.22))
                        HStack(spacing: 2) {
                            Image(systemName: "xmark")
                            Text("+\(Int(shop.haggleSurcharge * 100))%")
                        }
                        .foregroundStyle(Palette.crimson)
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .buttonStyle(.gamePlain)
                .accessibilityLabel("Haggle: answer a card for a discount")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.parchment))
        .overlay(alignment: .bottom) {
            // Speech-bubble tail pointing at the shopkeeper.
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.parchment)
                .offset(y: 9)
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

/// One item standing on a shop shelf, with its effect and a hanging price tag.
private struct ShelfWare<Art: View, Effect: View>: View {
    let price: Int
    let basePrice: Int
    let canBuy: Bool
    let isSold: Bool
    /// Shown instead of the price when the item can't be bought for a non-gold reason (bag full).
    let blockedIcon: String?
    @ViewBuilder var art: Art
    @ViewBuilder var effect: Effect
    var onBuy: () -> Void

    var body: some View {
        Button(action: onBuy) {
            VStack(spacing: 4) {
                effect
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                art.frame(height: 44)
                Group {
                    if isSold {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(red: 0.25, green: 0.5, blue: 0.22))
                    } else if let blockedIcon, !canBuy {
                        Image(systemName: blockedIcon).foregroundStyle(Palette.ink.opacity(0.5))
                    } else {
                        HStack(spacing: 3) {
                            GoldCoin(size: 11)
                            Text("\(price)").foregroundStyle(priceColor)
                        }
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.parchment))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(canBuy ? Palette.gold : Palette.ink.opacity(0.2), lineWidth: canBuy ? 1.5 : 1))
            }
            .frame(width: 70)
            .opacity(canBuy || isSold ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gamePlain)
        .disabled(!canBuy)
    }

    private var priceColor: Color {
        if price < basePrice { return Color(red: 0.25, green: 0.5, blue: 0.22) }
        if price > basePrice { return Palette.crimson }
        return Palette.ink
    }
}
