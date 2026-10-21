import SwiftUI
import SwiftData
import PhotosUI

/// Editable copy of an item, so Cancel really does throw changes away.
struct ItemDraft {
    var title = ""
    var format: MediaFormat = .dvd
    var year: Int?
    var director = ""
    var cast = ""
    var genre = ""
    var studio = ""
    var edition = ""
    var region = ""
    var videoStandard: VideoStandard = .unknown
    var aspectRatio = ""
    var runtimeMinutes: Int?
    var discCount = 1
    var laserDiscType: LaserDiscType = .unknown
    var platform = ""
    var vinylSize = ""
    var vinylSpeed = ""
    var barcode = ""
    var catalogNumber = ""
    var condition: ItemCondition = .unknown
    var isSealed = false
    var location = ""
    var purchasePrice: Double?
    var purchaseDate: Date?
    var purchasedFrom = ""
    var rating = 0
    var summary = ""
    var notes = ""
    var isWishlist = false
    var coverImage: Data?
    var estimatedValue: Double?
    var valueLow: Double?
    var valueHigh: Double?
    var valueCurrency = ""
    var valueSource = ""
    var valueUpdated: Date?

    init(from i: MediaItem) {
        title = i.title; format = i.format; year = i.year; director = i.director
        cast = i.cast; genre = i.genre; studio = i.studio; edition = i.edition
        region = i.region; videoStandard = i.videoStandard; aspectRatio = i.aspectRatio
        runtimeMinutes = i.runtimeMinutes; discCount = i.discCount
        laserDiscType = i.laserDiscType; platform = i.platform
        vinylSize = i.vinylSize; vinylSpeed = i.vinylSpeed
        barcode = i.barcode; catalogNumber = i.catalogNumber
        condition = i.condition; isSealed = i.isSealed; location = i.location
        purchasePrice = i.purchasePrice; purchaseDate = i.purchaseDate
        purchasedFrom = i.purchasedFrom; rating = i.rating; summary = i.summary
        notes = i.notes; isWishlist = i.isWishlist; coverImage = i.coverImage
        estimatedValue = i.estimatedValue; valueLow = i.valueLow; valueHigh = i.valueHigh
        valueCurrency = i.valueCurrency; valueSource = i.valueSource; valueUpdated = i.valueUpdated
    }

    func apply(to i: MediaItem) {
        i.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        i.format = format; i.year = year; i.director = director
        i.cast = format.kind == .video ? cast : ""
        i.genre = genre; i.studio = studio; i.edition = edition; i.region = region
        i.videoStandard = format.showsVideoStandard ? videoStandard : .unknown
        i.aspectRatio = format.kind == .video ? aspectRatio : ""
        i.runtimeMinutes = runtimeMinutes; i.discCount = max(1, discCount)
        i.laserDiscType = format == .laserDisc ? laserDiscType : .unknown
        i.platform = format == .game ? platform : ""
        i.vinylSize = format == .vinyl ? vinylSize : ""
        i.vinylSpeed = format == .vinyl ? vinylSpeed : ""
        i.barcode = barcode.trimmingCharacters(in: .whitespaces)
        i.catalogNumber = catalogNumber; i.condition = condition; i.isSealed = isSealed
        i.location = location; i.purchasePrice = purchasePrice; i.purchaseDate = purchaseDate
        i.purchasedFrom = purchasedFrom; i.rating = rating; i.summary = summary; i.notes = notes
        i.isWishlist = isWishlist; i.coverImage = coverImage
        i.estimatedValue = estimatedValue; i.valueLow = valueLow; i.valueHigh = valueHigh
        i.valueCurrency = valueCurrency.isEmpty && estimatedValue != nil
            ? (Locale.current.currency?.identifier ?? "GBP") : valueCurrency
        i.valueSource = valueSource; i.valueUpdated = valueUpdated
        i.dateModified = Date()
    }

    /// Fills only the empty fields, so nothing you've typed gets overwritten.
    /// The market value is always refreshed.
    mutating func merge(_ r: LookupResult) {
        func fill(_ field: inout String, _ value: String?) {
            if field.trimmingCharacters(in: .whitespaces).isEmpty, let value, !value.isEmpty { field = value }
        }
        if title.trimmingCharacters(in: .whitespaces).isEmpty, let f = r.format { format = f }
        fill(&title, r.title)
        if year == nil { year = r.year }
        fill(&director, r.creator)
        fill(&cast, r.cast)
        fill(&genre, r.genre)
        fill(&studio, r.studio)
        fill(&platform, r.platform)
        fill(&catalogNumber, r.catalogNumber)
        fill(&region, r.region)
        fill(&vinylSize, r.vinylSize)
        fill(&vinylSpeed, r.vinylSpeed)
        fill(&summary, r.summary)
        if runtimeMinutes == nil { runtimeMinutes = r.runtimeMinutes }
        if videoStandard == .unknown, let s = r.videoStandard { videoStandard = s }
        if coverImage == nil { coverImage = r.coverData }
        mergeValue(r)
    }

    mutating func mergeValue(_ r: LookupResult) {
        guard let v = r.value else { return }
        estimatedValue = v
        valueLow = r.valueLow
        valueHigh = r.valueHigh
        valueCurrency = r.valueCurrency ?? "USD"
        valueSource = r.valueSource ?? r.sources.joined(separator: ", ")
        valueUpdated = Date()
    }
}

struct ItemEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [MediaItem]

    let item: MediaItem
    let isNew: Bool

    @State private var draft: ItemDraft
    @State private var photoSelection: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var didAutoLookup = false

    init(item: MediaItem, isNew: Bool) {
        self.item = item
        self.isNew = isNew
        _draft = State(initialValue: ItemDraft(from: item))
    }

    private var currency: String { Locale.current.currency?.identifier ?? "GBP" }
    private var kind: MediaFormat.Kind { draft.format.kind }
    private var canLookUp: Bool {
        LookupSettings.isEnabled && draft.barcode.contains(where: \.isNumber) && !isLookingUp
    }

    private var duplicateWarning: String? {
        let code = draft.barcode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty,
              let other = allItems.first(where: { $0.barcode == code && $0.id != item.id })
        else { return nil }
        return "You already have \(other.displayTitle) (\(other.format.rawValue)) with this barcode."
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title, axis: .vertical)
                    .font(.headline)
                Picker("Format", selection: $draft.format) {
                    ForEach(MediaFormat.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                Toggle("On wishlist (don't own yet)", isOn: $draft.isWishlist)
            }

            barcodeSection

            Section("Cover") {
                HStack(spacing: 16) {
                    coverPreview
                    VStack(alignment: .leading, spacing: 12) {
                        PhotosPicker(selection: $photoSelection, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showingCamera = true } label: {
                                Label("Take photo", systemImage: "camera")
                            }
                        }
                        if draft.coverImage != nil {
                            Button(role: .destructive) { draft.coverImage = nil } label: {
                                Label("Remove", systemImage: "xmark.circle")
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section(kind == .music ? "Music" : kind == .game ? "Game" : "Film") {
                TextField(draft.format.creatorLabel, text: $draft.director)
                TextField("Year", value: $draft.year, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                if kind == .game {
                    TextField("Platform (e.g. PlayStation 2, Mega Drive)", text: $draft.platform)
                }
                if kind == .video {
                    TextField("Cast", text: $draft.cast, axis: .vertical)
                }
                TextField("Genre", text: $draft.genre)
                TextField(draft.format.studioLabel, text: $draft.studio)
                if kind != .game {
                    TextField("Running time (minutes)", value: $draft.runtimeMinutes, format: .number)
                        .keyboardType(.numberPad)
                }
                TextField("Summary", text: $draft.summary, axis: .vertical)
                    .lineLimit(1...6)
            }

            Section("Release") {
                TextField("Edition (e.g. Special Edition, Big Box)", text: $draft.edition)
                TextField(regionPlaceholder, text: $draft.region)
                if draft.format.showsVideoStandard {
                    Picker("Video standard", selection: $draft.videoStandard) {
                        ForEach(VideoStandard.allCases) { Text($0.label).tag($0) }
                    }
                }
                if kind == .video {
                    TextField("Aspect ratio (e.g. 2.35:1, 4:3)", text: $draft.aspectRatio)
                }
                if draft.format == .vinyl {
                    Picker("Size", selection: $draft.vinylSize) {
                        Text("Not set").tag("")
                        ForEach(["7\"", "10\"", "12\""], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Speed (RPM)", selection: $draft.vinylSpeed) {
                        Text("Not set").tag("")
                        ForEach(["33⅓", "45", "78"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Stepper("\(draft.format.unitName): \(draft.discCount)",
                        value: $draft.discCount, in: 1...50)
                if draft.format == .laserDisc {
                    Picker("Disc type", selection: $draft.laserDiscType) {
                        ForEach(LaserDiscType.allCases) { Text($0.label).tag($0) }
                    }
                }
                TextField("Catalogue number", text: $draft.catalogNumber)
            }

            Section {
                TextField("Estimated value", value: $draft.estimatedValue,
                          format: .currency(code: draft.valueCurrency.isEmpty ? currency : draft.valueCurrency))
                    .keyboardType(.decimalPad)
                if let low = draft.valueLow, let high = draft.valueHigh, high > low {
                    LabeledContent("Range") {
                        Text("\(money(low)) – \(money(high))")
                    }
                }
            } header: {
                Text("Value")
            } footer: {
                if !draft.valueSource.isEmpty, let date = draft.valueUpdated {
                    Text("\(draft.valueSource), \(date.formatted(date: .abbreviated, time: .omitted)). A rough guide only.")
                }
            }

            Section("Your copy") {
                Picker("Condition", selection: $draft.condition) {
                    ForEach(ItemCondition.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Still sealed", isOn: $draft.isSealed)
                TextField("Location (shelf, box…)", text: $draft.location)
                HStack {
                    Text("Rating")
                    Spacer()
                    StarRating(rating: $draft.rating)
                }
                TextField("Price paid", value: $draft.purchasePrice, format: .currency(code: currency))
                    .keyboardType(.decimalPad)
                Toggle("Purchase date", isOn: Binding(
                    get: { draft.purchaseDate != nil },
                    set: { draft.purchaseDate = $0 ? (draft.purchaseDate ?? Date()) : nil }
                ))
                if draft.purchaseDate != nil {
                    DatePicker("Bought on", selection: Binding(
                        get: { draft.purchaseDate ?? Date() },
                        set: { draft.purchaseDate = $0 }
                    ), displayedComponents: .date)
                }
                TextField("Bought from", text: $draft.purchasedFrom)
            }

            Section("Notes") {
                TextField("Anything else", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .navigationTitle(isNew ? "Add Item" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task {
            // Arrived here from a scan: look it up straight away.
            guard isNew, !didAutoLookup, draft.title.isEmpty, canLookUp else { return }
            didAutoLookup = true
            await lookUp()
        }
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    draft.coverImage = ImageTools.compressedCover(from: data)
                }
                photoSelection = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                if let image, let data = image.jpegData(compressionQuality: 0.9) {
                    draft.coverImage = ImageTools.compressedCover(from: data)
                }
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScanSheet { code in
                draft.barcode = code
                showingScanner = false
                if draft.title.isEmpty, canLookUp {
                    Task { await lookUp() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var barcodeSection: some View {
        Section {
            HStack {
                TextField("Barcode", text: $draft.barcode)
                    .keyboardType(.numberPad)
                if BarcodeScannerView.isAvailable {
                    Button { showingScanner = true } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Scan barcode")
                }
            }
            if let duplicateWarning {
                Label(duplicateWarning, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if LookupSettings.isEnabled {
                Button {
                    Task { await lookUp() }
                } label: {
                    HStack {
                        Label("Look up details & value online", systemImage: "globe")
                        if isLookingUp {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canLookUp)
            }
            if let lookupMessage {
                Text(lookupMessage).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Barcode")
        } footer: {
            if LookupSettings.isEnabled {
                Text("Fills in empty fields only — nothing you've typed is replaced.")
            }
        }
    }

    private func lookUp() async {
        isLookingUp = true
        lookupMessage = nil
        let outcome = await LookupService.shared.lookup(barcode: draft.barcode, formatHint: draft.format)
        draft.merge(outcome.result)
        lookupMessage = outcome.summaryText
        isLookingUp = false
    }

    private func money(_ v: Double) -> String {
        v.formatted(.currency(code: draft.valueCurrency.isEmpty ? currency : draft.valueCurrency))
    }

    private var regionPlaceholder: String {
        switch draft.format {
        case .dvd: return "Region (e.g. 2, 1, 0/All)"
        case .vhs: return "Country / release (e.g. UK rental)"
        case .laserDisc, .vinyl, .cd: return "Country (e.g. UK, Japan, USA)"
        case .game: return "Region (e.g. PAL UK, NTSC-J)"
        }
    }

    private var coverPreview: some View {
        let width: CGFloat = 70
        let height = width * draft.format.coverAspect
        return Group {
            if let data = draft.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: draft.format.symbol).font(.title2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func save() {
        draft.apply(to: item)
        if isNew { context.insert(item) }
        try? context.save()
        dismiss()
    }
}

struct StarRating: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Color.orange : Color.secondary)
                    .onTapGesture { rating = (rating == star) ? 0 : star }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }
}
