import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: MediaItem

    @State private var editing = false
    @State private var confirmDelete = false
    @State private var showCoverFull = false
    @State private var refreshingValue = false
    @State private var valueMessage: String?

    private var kind: MediaFormat.Kind { item.format.kind }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    CoverThumbnail(item: item, width: 110)
                        .onTapGesture { if item.coverImage != nil { showCoverFull = true } }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle).font(.title2.bold())
                        if kind == .music, !item.director.isEmpty {
                            Text(item.director).font(.headline)
                        }
                        Label(item.format == .game && !item.platform.isEmpty
                              ? item.platform : item.format.rawValue,
                              systemImage: item.format.symbol)
                            .foregroundStyle(.secondary)
                        if let year = item.year {
                            Text(String(year)).foregroundStyle(.secondary)
                        }
                        if item.rating > 0 {
                            Text(String(repeating: "★", count: item.rating)
                                 + String(repeating: "☆", count: 5 - item.rating))
                                .foregroundStyle(.orange)
                        }
                        if item.isWishlist {
                            Text("WISHLIST").font(.caption.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if !item.summary.isEmpty {
                Section { Text(item.summary) }
            }

            Section(kind == .music ? "Music" : kind == .game ? "Game" : "Film") {
                if kind != .music { row(item.format.creatorLabel, item.director) }
                if kind == .game { row("Platform", item.platform) }
                row("Cast", item.cast)
                row("Genre", item.genre)
                row(item.format.studioLabel, item.studio)
                row("Running time", item.runtimeMinutes.map { "\($0) min" } ?? "")
            }

            Section("Release") {
                row("Edition", item.edition)
                row("Region", item.region)
                if item.format.showsVideoStandard {
                    row("Video standard", item.videoStandard == .unknown ? "" : item.videoStandard.rawValue)
                }
                row("Aspect ratio", item.aspectRatio)
                if item.format == .vinyl {
                    row("Size", item.vinylSize)
                    row("Speed", item.vinylSpeed.isEmpty ? "" : "\(item.vinylSpeed) RPM")
                }
                row(item.format.unitName, item.discCount > 1 ? "\(item.discCount)" : "")
                if item.format == .laserDisc {
                    row("Disc type", item.laserDiscType == .unknown ? "" : item.laserDiscType.rawValue)
                }
                row("Barcode", item.barcode)
                row("Catalogue no.", item.catalogNumber)
            }

            valueSection

            Section("Your copy") {
                row("Condition", item.condition == .unknown ? "" : item.condition.rawValue)
                if item.isSealed { row("Sealed", "Yes") }
                row("Location", item.location)
                row("Paid", item.purchasePrice.map {
                    $0.formatted(.currency(code: Locale.current.currency?.identifier ?? "GBP"))
                } ?? "")
                row("Bought", item.purchaseDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
                row("From", item.purchasedFrom)
            }

            if !item.notes.isEmpty {
                Section("Notes") {
                    Text(item.notes)
                }
            }

            Section {
                if item.isWishlist {
                    Button {
                        item.isWishlist = false
                        item.dateModified = Date()
                    } label: {
                        Label("Got it — move to collection", systemImage: "checkmark.circle")
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } footer: {
                Text("Added \(item.dateAdded.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { ItemEditView(item: item, isNew: false) }
        }
        .sheet(isPresented: $showCoverFull) {
            if let data = item.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                    .padding()
                    .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("Delete \(item.displayTitle)?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(item)
                try? context.save()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        let canRefresh = LookupSettings.isEnabled && item.barcode.contains(where: \.isNumber)
        if item.estimatedValue != nil || canRefresh {
            Section {
                if let value = item.formattedValue {
                    LabeledContent("Estimated value") {
                        Text(value).bold()
                    }
                    if let low = item.valueLow, let high = item.valueHigh, high > low {
                        let code = item.valueCurrency.isEmpty ? "USD" : item.valueCurrency
                        row("Range", "\(low.formatted(.currency(code: code))) – \(high.formatted(.currency(code: code)))")
                    }
                }
                if canRefresh {
                    Button {
                        Task { await refreshValue() }
                    } label: {
                        HStack {
                            Label(item.estimatedValue == nil ? "Look up value online" : "Update value",
                                  systemImage: "arrow.clockwise")
                            if refreshingValue { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(refreshingValue)
                }
                if let valueMessage {
                    Text(valueMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Value")
            } footer: {
                if !item.valueSource.isEmpty, let date = item.valueUpdated {
                    Text("\(item.valueSource), \(date.formatted(date: .abbreviated, time: .omitted)). A rough guide only — condition and edition matter a lot.")
                }
            }
        }
    }

    private func refreshValue() async {
        refreshingValue = true
        valueMessage = nil
        let outcome = await LookupService.shared.lookup(barcode: item.barcode,
                                                        formatHint: item.format,
                                                        includeCover: item.coverImage == nil)
        var draft = ItemDraft(from: item)
        if outcome.result.value != nil {
            draft.mergeValue(outcome.result)
            if draft.coverImage == nil { draft.coverImage = outcome.result.coverData }
            draft.apply(to: item)
            try? context.save()
            valueMessage = outcome.problems.isEmpty ? nil : outcome.problems.joined(separator: "\n")
        } else {
            valueMessage = (["No price found online."] + outcome.problems).joined(separator: "\n")
        }
        refreshingValue = false
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label) {
                Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
        }
    }
}
