import SwiftUI
import PhotosUI
import SceneKit
import UniformTypeIdentifiers

// MARK: - MasteryBar (game.md §4)

/// Accuracy bar: ≥80% green, ≥50% gold, below that red, grey when there's no data yet.
/// Darkened versions of the semantic accuracy colors — the normal palette accents are too light
/// to read as small text on parchment.
private func accuracyTint(_ accuracy: Double) -> Color {
    if accuracy >= 0.8 { return Color(red: 0.24, green: 0.40, blue: 0.21) }
    if accuracy >= 0.5 { return Color(red: 0.45, green: 0.34, blue: 0.10) }
    return Color(red: 0.55, green: 0.15, blue: 0.13)
}

struct MasteryBar: View {
    var accuracy: Double?

    private var color: Color {
        guard let accuracy else { return Color.gray.opacity(0.4) }
        if accuracy >= 0.8 { return Palette.moss }
        if accuracy >= 0.5 { return Palette.gold }
        return Palette.ember
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.14))
                // No history yet = an empty track, not a full grey bar that reads as "100%".
                if let accuracy {
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geometry.size.width * accuracy))
                }
            }
        }
        .frame(height: 6)
    }
}

// MARK: - ImageSlotView (game.md §4)

/// A thumbnail with a menu to pick a photo, take one with the camera, or remove the current image.
struct ImageSlotView: View {
    @Binding var imageID: String?
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cachedImage: PlatformImage?

    var body: some View {
        Menu {
            PhotosPicker("Photo Library", selection: $photosPickerItem, matching: .images)
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") { showingCamera = true }
            }
            #endif
            if imageID != nil {
                Button("Remove", role: .destructive) {
                    if let imageID { CardImageStore.delete(imageID) }
                    imageID = nil
                    cachedImage = nil
                }
            }
        } label: {
            thumbnail
        }
        .onChange(of: photosPickerItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = PlatformImage(data: data) else { return }
                if let imageID { CardImageStore.delete(imageID) }
                imageID = CardImageStore.save(image)
                cachedImage = image
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                guard let image else { return }
                if let imageID { CardImageStore.delete(imageID) }
                imageID = CardImageStore.save(image)
                cachedImage = image
            }
        }
        #endif
        .task(id: imageID) {
            guard let imageID else {
                cachedImage = nil
                return
            }
            cachedImage = CardImageStore.load(imageID)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let cachedImage {
            Image(platformImage: cachedImage)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.parchmentShade.opacity(0.45))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(Palette.ink.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1)
                )
        }
    }
}

#if os(iOS)
private struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (PlatformImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onPick: (PlatformImage?) -> Void
        init(onPick: @escaping (PlatformImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? PlatformImage)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
            picker.dismiss(animated: true)
        }
    }
}
#endif

// MARK: - CardEditorView (game.md §4)

/// Small inline preview of a `CardFace`'s picture (image, SF Symbol, or hex color swatch).
struct CardFaceThumbnailView: View {
    var face: CardFace
    var size: CGFloat = 38

    var body: some View {
        if let imageID = face.imageID, let uiImage = CardImageStore.load(imageID) {
            Image(platformImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ink.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1))
        } else if let symbol = face.symbol, !symbol.isEmpty {
            Image(systemName: symbol)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(face.color.map { Color(hex: $0) } ?? Palette.ink)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ink.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1))
        } else if let color = face.color, !color.isEmpty {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: color))
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.ink.opacity(0.28), lineWidth: 1.5))
        }
    }
}

/// Question, correct answer, and optional author-written wrong answers. Save is disabled until
/// the card passes `Flashcard.validationIssues`.
struct CardEditorView: View {
    @Environment(DeckStore.self) private var deckStore
    @Environment(CardStatsStore.self) private var statsStore
    @Environment(\.dismiss) private var dismiss

    let deckID: UUID
    let cardWeightConfig: CardWeightConfig
    let isNew: Bool
    @State private var card: Flashcard

    init(deckID: UUID, card: Flashcard? = nil, cardWeightConfig: CardWeightConfig) {
        self.deckID = deckID
        self.cardWeightConfig = cardWeightConfig
        _card = State(initialValue: card ?? Flashcard(question: CardFace(), answer: CardFace()))
        isNew = card == nil
    }

    var body: some View {
        Form {
            Section {
                let stats = statsStore.stats(for: card.id)
                if stats.total > 0 {
                    let pct = Int((Double(stats.correct) / Double(stats.total)) * 100)
                    Text("Forward: \(pct)% · \(stats.correct)/\(stats.total)")
                        .font(.readable(14))
                } else {
                    Text("Forward: Not answered yet").font(.readable(14)).foregroundStyle(Palette.ink.opacity(0.6))
                }
                let revStats = statsStore.stats(for: card.reverseID)
                if revStats.total > 0 {
                    let pct = Int((Double(revStats.correct) / Double(revStats.total)) * 100)
                    Text("Reverse: \(pct)% · \(revStats.correct)/\(revStats.total)")
                        .font(.readable(13))
                        .foregroundStyle(Palette.ink.opacity(0.75))
                }
                let weight = statsStore.weight(for: card.id, config: cardWeightConfig)
                let multStr = String(format: "%.1f", weight / cardWeightConfig.noHistory)
                Text("Drawn \(multStr)× as often as an unseen card")
                    .font(.readable(12))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            } header: {
                sectionHeader("Accuracy")
            }
            .listRowBackground(Palette.parchment)

            Section {
                TextField("Question text", text: questionTextBinding, axis: .vertical)
                HStack(spacing: 12) {
                    ImageSlotView(imageID: $card.question.imageID)
                    if card.question.symbol != nil || card.question.color != nil {
                        CardFaceThumbnailView(face: CardFace(symbol: card.question.symbol, color: card.question.color), size: 48)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("SF Symbol (optional)", text: questionSymbolBinding)
                            .font(.system(size: 13, design: .monospaced))
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                        TextField("Hex color #RRGGBB (optional)", text: questionColorBinding)
                            .font(.system(size: 13, design: .monospaced))
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                    }
                }
            } header: {
                sectionHeader("Question")
            }
            .listRowBackground(Palette.parchment)

            Section {
                TextField("Answer text", text: answerTextBinding, axis: .vertical)
                HStack(spacing: 12) {
                    ImageSlotView(imageID: $card.answer.imageID)
                    if card.answer.symbol != nil || card.answer.color != nil {
                        CardFaceThumbnailView(face: CardFace(symbol: card.answer.symbol, color: card.answer.color), size: 48)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("SF Symbol (optional)", text: answerSymbolBinding)
                            .font(.system(size: 13, design: .monospaced))
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                        TextField("Hex color #RRGGBB (optional)", text: answerColorBinding)
                            .font(.system(size: 13, design: .monospaced))
                            .noAutocapitalization()
                            .autocorrectionDisabled()
                    }
                }
            } header: {
                sectionHeader("Correct answer")
            }
            .listRowBackground(Palette.parchment)

            Section {
                TextField("Prompt above question (e.g. Was ist das?)", text: promptBinding)
                    .font(.readable(14))
                TextField("Hint behind light-bulb button (optional)", text: hintBinding, axis: .vertical)
                    .font(.readable(14))
                TextField("Explanation shown after answering (optional)", text: explanationBinding, axis: .vertical)
                    .font(.readable(14))
                Toggle("Allow asking in reverse", isOn: reversibleBinding)
                    .font(.readable(14))
                    .tint(Palette.moss)
            } header: {
                sectionHeader("Study details (optional)")
            }
            .listRowBackground(Palette.parchment)

            Section {
                ForEach(Array(card.wrongAnswers.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField("Wrong answer", text: wrongAnswerTextBinding(index), axis: .vertical)
                        if card.wrongAnswers[index].symbol != nil || card.wrongAnswers[index].color != nil {
                            CardFaceThumbnailView(face: card.wrongAnswers[index], size: 36)
                        }
                        ImageSlotView(imageID: wrongAnswerImageBinding(index))
                    }
                }
                .onDelete { card.wrongAnswers.remove(atOffsets: $0) }
                Button("Add wrong answer") { card.wrongAnswers.append(CardFace()) }
                    .font(.readable(14))
            } header: {
                sectionHeader("Wrong answers (optional)")
            } footer: {
                Text("Empty slots are filled with correct answers from other cards in this deck when the card is shown.")
                    .font(.readable(11))
                    .foregroundStyle(Palette.textDim)
            }
            .listRowBackground(Palette.parchment)

            if !card.validationIssues.isEmpty {
                Section {
                    ForEach(card.validationIssues, id: \.self) { issue in
                        Text(issue).font(.readable(13)).foregroundStyle(Palette.ember)
                    }
                } header: {
                    sectionHeader("Can't save yet")
                }
                .listRowBackground(Palette.parchment)
            }
        }
        .deskList()
        .themedNavigationBar()
        .navigationTitle(isNew ? "New Card" : "Edit Card")
        .toolbar {
            #if os(macOS)
            // Mac sheets can't be swiped away; Esc also triggers this (game.md §15).
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            #endif
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if isNew {
                        deckStore.addCard(card, toDeck: deckID)
                    } else {
                        deckStore.updateCard(card, inDeck: deckID)
                    }
                    dismiss()
                }
                .buttonStyle(QuestButtonStyle(kind: .quiet))
                .disabled(!card.isValid)
            }
        }
    }

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        SectionHeaderLabel(text: text)
    }

    private var questionTextBinding: Binding<String> {
        Binding(get: { card.question.text ?? "" }, set: { card.question.text = $0.isEmpty ? nil : $0 })
    }

    private var questionSymbolBinding: Binding<String> {
        Binding(get: { card.question.symbol ?? "" }, set: { card.question.symbol = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) })
    }

    private var questionColorBinding: Binding<String> {
        Binding(get: { card.question.color ?? "" }, set: { card.question.color = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) })
    }

    private var answerTextBinding: Binding<String> {
        Binding(get: { card.answer.text ?? "" }, set: { card.answer.text = $0.isEmpty ? nil : $0 })
    }

    private var answerSymbolBinding: Binding<String> {
        Binding(get: { card.answer.symbol ?? "" }, set: { card.answer.symbol = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) })
    }

    private var answerColorBinding: Binding<String> {
        Binding(get: { card.answer.color ?? "" }, set: { card.answer.color = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) })
    }

    private var promptBinding: Binding<String> {
        Binding(get: { card.prompt ?? "" }, set: { card.prompt = $0.isEmpty ? nil : $0 })
    }

    private var hintBinding: Binding<String> {
        Binding(get: { card.hint ?? "" }, set: { card.hint = $0.isEmpty ? nil : $0 })
    }

    private var explanationBinding: Binding<String> {
        Binding(get: { card.explanation ?? "" }, set: { card.explanation = $0.isEmpty ? nil : $0 })
    }

    private var reversibleBinding: Binding<Bool> {
        Binding(get: { card.reversible ?? true }, set: { card.reversible = $0 ? nil : false })
    }

    private func wrongAnswerTextBinding(_ index: Int) -> Binding<String> {
        Binding(get: { card.wrongAnswers[index].text ?? "" }, set: { card.wrongAnswers[index].text = $0.isEmpty ? nil : $0 })
    }

    private func wrongAnswerImageBinding(_ index: Int) -> Binding<String?> {
        Binding(get: { card.wrongAnswers[index].imageID }, set: { card.wrongAnswers[index].imageID = $0 })
    }
}

// MARK: - DeckEditorView (game.md §4)

/// A deck's cards: question preview, per-card accuracy, add/delete/reorder, and a sort toggle.
struct DeckEditorView: View {
    @Environment(DeckStore.self) private var deckStore
    @Environment(CardStatsStore.self) private var statsStore
    @Environment(\.dismiss) private var dismiss

    let deckID: UUID
    let cardWeightConfig: CardWeightConfig
    let minDeckSize: Int

    @State private var sortWeakestFirst = false
    @State private var editingCard: Flashcard?
    @State private var isAddingCard = false
    @State private var showingDeleteDeckConfirmation = false

    private var deck: Deck? {
        deckStore.decks.first { $0.id == deckID }
    }

    private var sortedCards: [Flashcard] {
        guard let deck else { return [] }
        guard sortWeakestFirst else { return deck.cards }
        return deck.cards.sorted {
            (combinedAccuracy(for: $0, in: deck) ?? -1) < (combinedAccuracy(for: $1, in: deck) ?? -1)
        }
    }

    var body: some View {
        List {
            if let deck {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink.opacity(0.7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ask cards both ways")
                                .font(.readable(15, .semibold))
                            Text("Also quizzes Answer → Question for reversible cards")
                                .font(.readable(11))
                                .foregroundStyle(Palette.ink.opacity(0.6))
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { deck.includesReverse },
                            set: { deckStore.setReverseCards(deckID, enabled: $0) }
                        ))
                        .labelsHidden()
                        .tint(Palette.moss)
                    }
                    .parchmentRow()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if deck.cards.count < minDeckSize {
                    Section {
                        Text(minDeckSize - deck.cards.count == 1
                             ? "Needs 1 more card before this deck can be used in a run."
                             : "Needs \(minDeckSize - deck.cards.count) more cards before this deck can be used in a run.")
                            .font(.readable(13))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                            .parchmentRow()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            ForEach(sortedCards) { card in
                Button {
                    editingCard = card
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        if let thumbFace = thumbnailFace(for: card) {
                            CardFaceThumbnailView(face: thumbFace, size: 40)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(cardSummary(card))
                                .font(.readable(15, .semibold))
                                .lineLimit(2)
                            if let explanation = card.explanation, !explanation.isEmpty {
                                Text(explanation)
                                    .font(.readable(12))
                                    .foregroundStyle(Palette.ink.opacity(0.65))
                                    .lineLimit(1)
                            }
                            let stats = combinedStats(for: card, in: deck)
                            if stats.total > 0 {
                                HStack(spacing: 8) {
                                    let acc = Double(stats.correct) / Double(stats.total)
                                    MasteryBar(accuracy: acc).frame(width: 70)
                                    Text("\(Int(acc * 100))% · \(stats.correct)/\(stats.total)")
                                        .font(.readable(12))
                                        .foregroundStyle(Palette.ink.opacity(0.65))
                                }
                            } else {
                                Text("Not answered yet").font(.readable(12)).foregroundStyle(Palette.ink.opacity(0.5))
                            }
                        }
                        Spacer(minLength: 8)
                        if let accuracy = combinedAccuracy(for: card, in: deck) {
                            Text("\(Int(accuracy * 100))%")
                                .font(.readable(14, .bold))
                                .foregroundStyle(accuracyTint(accuracy))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Palette.ink.opacity(0.08)))
                        }
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink.opacity(0.3))
                    }
                    .parchmentRow()
                }
                .buttonStyle(.gamePlain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button("Reset stats", role: .destructive) {
                        statsStore.reset(cardID: card.id)
                    }
                    #if os(macOS)
                    // Mac has no swipe-to-delete or Edit button for cards (game.md §15).
                    Button("Delete Card", role: .destructive) {
                        deckStore.deleteCard(card.id, fromDeck: deckID)
                    }
                    #endif
                }
            }
            .onDelete { offsets in
                guard let deck else { return }
                for index in offsets {
                    deckStore.deleteCard(deck.cards[index].id, fromDeck: deckID)
                }
            }
            .onMove { from, to in
                deckStore.moveCards(inDeck: deckID, fromOffsets: from, toOffset: to)
            }

            if let deck {
                Section {
                    Button(role: .destructive) {
                        showingDeleteDeckConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                            Text("Delete Deck")
                            Spacer()
                        }
                        .font(.readable(15, .semibold))
                        .foregroundStyle(Palette.ember)
                        .parchmentRow()
                    }
                    .buttonStyle(.gamePlain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .compactListSections()
        .deskList()
        .themedNavigationBar()
        .navigationTitle(deck?.name ?? L("Deck"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Card") { isAddingCard = true }
                    .buttonStyle(QuestButtonStyle(kind: .quiet))
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(sortWeakestFirst ? "Your Order" : "Weakest First") {
                    sortWeakestFirst.toggle()
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
            }
            #endif
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete Deck", role: .destructive) {
                    showingDeleteDeckConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(deck?.name ?? L("Deck"))\"?",
            isPresented: $showingDeleteDeckConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Deck", role: .destructive) {
                if let deck {
                    statsStore.reset(deck: deck)
                    deckStore.deleteDeck(deck.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this deck and its \(deck?.cards.count ?? 0) cards.")
        }
        .sheet(isPresented: $isAddingCard) {
            NavigationStack {
                CardEditorView(deckID: deckID, cardWeightConfig: cardWeightConfig)
            }
            .gameSheetFrame()
        }
        .sheet(item: $editingCard) { card in
            NavigationStack {
                CardEditorView(deckID: deckID, card: card, cardWeightConfig: cardWeightConfig)
            }
            .gameSheetFrame()
        }
    }

    private func thumbnailFace(for card: Flashcard) -> CardFace? {
        if card.question.hasPicture { return card.question }
        if card.answer.hasPicture { return card.answer }
        return nil
    }

    private func faceLabel(_ face: CardFace) -> String {
        if let text = face.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        if face.imageID != nil { return L("[Picture]") }
        if let sym = face.symbol, !sym.isEmpty { return "[\(sym)]" }
        if let col = face.color, !col.isEmpty { return "[\(col)]" }
        return L("Untitled")
    }

    private func cardSummary(_ card: Flashcard) -> String {
        let q = faceLabel(card.question)
        let a = faceLabel(card.answer)
        if card.question.isPictureOnly && !card.answer.isPictureOnly {
            return a
        }
        return "\(q) → \(a)"
    }

    private func combinedStats(for card: Flashcard, in deck: Deck?) -> (correct: Int, total: Int) {
        let fwd = statsStore.stats(for: card.id)
        guard deck?.includesReverse == true, card.reversible != false else { return fwd }
        let rev = statsStore.stats(for: card.reverseID)
        return (correct: fwd.correct + rev.correct, total: fwd.total + rev.total)
    }

    private func combinedAccuracy(for card: Flashcard, in deck: Deck?) -> Double? {
        let s = combinedStats(for: card, in: deck)
        guard s.total > 0 else { return nil }
        return Double(s.correct) / Double(s.total)
    }
}

// MARK: - DeckListView (game.md §4)

/// The deck manager: list of decks with card count, accuracy, and a "needs N more cards" badge.
struct DeckListView: View {
    @Environment(DeckStore.self) private var deckStore
    @Environment(CardStatsStore.self) private var statsStore

    let cardWeightConfig: CardWeightConfig
    let minDeckSize: Int
    /// Bundled sample decks (game.md §4.5), offered when the list is empty or one was deleted.
    var starterDecks: [Deck] = []

    @State private var isAddingDeck = false
    @State private var newDeckName = ""
    @State private var isImporting = false
    @State private var importProgress: DeckImporter.Progress?
    @State private var importReport: DeckImporter.Report?
    @State private var deckToDelete: Deck?
    @State private var showingDeleteConfirmation = false
    @State private var openDeckID: UUID?

    var body: some View {
        List {
            ForEach(deckStore.decks) { deck in
                // A plain button + navigationDestination: a NavigationLink row gets a system
                // chevron outside the parchment card.
                Button {
                    openDeckID = deck.id
                } label: {
                    HStack(spacing: 12) {
                        if let icon = deck.icon {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(deck.color.map { Color(hex: $0) } ?? Palette.ink)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Palette.ink.opacity(0.85)))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(deck.name).font(.readable(17, .semibold))
                                if let subtitle = deck.subtitle {
                                    Text(subtitle).font(.readable(12)).italic().foregroundStyle(Palette.ink.opacity(0.6))
                                }
                                if deck.includesReverse {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Palette.ink.opacity(0.5))
                                }
                            }
                            HStack(spacing: 8) {
                                MasteryBar(accuracy: statsStore.deckAccuracy(deck)).frame(width: 70)
                                Text(deck.cards.count == 1 ? "1 card" : "\(deck.cards.count) cards")
                                    .font(.readable(12))
                                    .foregroundStyle(Palette.ink.opacity(0.65))
                                if deck.cards.count < minDeckSize {
                                    Text("Needs \(minDeckSize - deck.cards.count) more")
                                        .font(.readable(12))
                                        .foregroundStyle(Palette.ember)
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        if let accuracy = statsStore.deckAccuracy(deck) {
                            Text("\(Int(accuracy * 100))%")
                                .font(.readable(15, .bold))
                                .foregroundStyle(accuracyTint(accuracy))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Palette.ink.opacity(0.08)))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.ink.opacity(0.35))
                    }
                    .parchmentRow()
                }
                .buttonStyle(.gamePlain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        deckToDelete = deck
                        showingDeleteConfirmation = true
                    }
                    Button("Reset Stats") {
                        statsStore.reset(deck: deck)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        deckToDelete = deck
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Deck", systemImage: "trash")
                    }
                    Button {
                        statsStore.reset(deck: deck)
                    } label: {
                        Label("Reset Stats", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .onDelete { offsets in
                if let firstIndex = offsets.first, firstIndex < deckStore.decks.count {
                    deckToDelete = deckStore.decks[firstIndex]
                    showingDeleteConfirmation = true
                }
            }
            .onMove { from, to in
                deckStore.moveDecks(fromOffsets: from, toOffset: to)
            }
        }
        .confirmationDialog(
            "Delete \"\(deckToDelete?.name ?? L("Deck"))\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Deck", role: .destructive) {
                if let deck = deckToDelete {
                    statsStore.reset(deck: deck)
                    deckStore.deleteDeck(deck.id)
                    deckToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deckToDelete = nil
            }
        } message: {
            if let deck = deckToDelete {
                Text("This will permanently delete \"\(deck.name)\" and its \(deck.cards.count) cards.")
            } else {
                Text("This will permanently delete this deck.")
            }
        }
        .compactListSections()
        .deskList()
        .themedNavigationBar()
        .navigationTitle("Decks")
        .navigationDestination(item: $openDeckID) { deckID in
            DeckEditorView(deckID: deckID, cardWeightConfig: cardWeightConfig, minDeckSize: minDeckSize)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Deck") { isAddingDeck = true }
                    .buttonStyle(QuestButtonStyle(kind: .quiet))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(QuestButtonStyle(kind: .quiet))
                .disabled(importProgress != nil)
            }
            #if os(iOS)
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
            }
            #endif
            if deckStore.isMissingStarterDecks(starterDecks) {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        deckStore.addStarterDecks(currentLanguageStarterDecks)
                    } label: {
                        Label("Add Starter Decks", systemImage: "sparkles.rectangle.stack")
                    }
                }
            }
        }
        .overlay {
            if deckStore.decks.isEmpty, importProgress == nil {
                emptyState
            }
        }
        .overlay {
            if let progress = importProgress {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text("Importing Decks…")
                                .font(.readable(18, .bold))
                                .foregroundStyle(Palette.ink)
                        }

                        if !progress.currentDeckName.isEmpty {
                            Text("\(progress.currentDeckName) (\(progress.currentFileIndex)/\(max(1, progress.totalFiles)))")
                                .font(.readable(14, .semibold))
                                .foregroundStyle(Palette.ink.opacity(0.8))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Palette.ink.opacity(0.15))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Palette.moss, Palette.gold],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(8, geo.size.width * progress.fractionCompleted))
                                    .animation(.easeOut(duration: 0.15), value: progress.fractionCompleted)
                            }
                            .overlay(
                                Capsule().strokeBorder(Palette.ink.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .frame(width: 240, height: 12)

                        Text("\(progress.completedCards) / \(progress.totalCards) cards (\(Int(progress.fractionCompleted * 100))%)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.ink.opacity(0.65))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .parchment()
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                }
                .transition(.opacity)
            }
        }
        // Pick deck .json files or whole folders (e.g. an exported deck collection) — game.md §4.4.
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importProgress = DeckImporter.Progress(
                    currentFileIndex: 0,
                    totalFiles: 1,
                    currentDeckName: L("Preparing files…"),
                    completedCards: 0,
                    totalCards: 0
                )
                Task { @MainActor in
                    let report = await DeckImporter.importItemsAsync(at: urls, into: deckStore) { prog in
                        importProgress = prog
                    }
                    importProgress = nil
                    importReport = report
                }
            case .failure(let error):
                importReport = DeckImporter.Report(errors: [error.localizedDescription])
            }
        }
        .alert("Import", isPresented: Binding(get: { importReport != nil }, set: { if !$0 { importReport = nil } })) {
            Button("OK", role: .cancel) { importReport = nil }
        } message: {
            Text(importReport?.summary ?? "")
        }
        .alert("New Deck", isPresented: $isAddingDeck) {
            TextField("Deck name", text: $newDeckName)
            Button("Cancel", role: .cancel) { newDeckName = "" }
            Button("Create") {
                guard !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                deckStore.createDeck(name: newDeckName)
                newDeckName = ""
            }
        }
    }

    /// The bundled decks re-read in the current language (they were loaded at launch, perhaps in
    /// another one — game.md §13 "Localization").
    private var currentLanguageStarterDecks: [Deck] {
        (try? ContentLoader.loadStarterDecks(minDeckSize: minDeckSize)) ?? starterDecks
    }

    /// Shown instead of a blank screen when there are no decks at all.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(0.7))
            Text("No decks yet")
                .font(.readable(20, .bold))
            Text("Every skill in a fight is cast by answering one of your flashcards. Write your own deck, import one, or start with the sample decks.")
                .font(.readable(13))
                .foregroundStyle(Palette.ink.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                if !starterDecks.isEmpty {
                    Button {
                        deckStore.addStarterDecks(currentLanguageStarterDecks)
                    } label: {
                        Label("Add Starter Decks", systemImage: "sparkles")
                    }
                    .buttonStyle(QuestButtonStyle(kind: .primary))
                }
                Button {
                    isAddingDeck = true
                } label: {
                    Label("New Deck", systemImage: "plus")
                }
                .buttonStyle(QuestButtonStyle(kind: .secondary))
            }
            .padding(.top, 4)
        }
        .parchment(padding: 24)
        .padding()
    }
}
