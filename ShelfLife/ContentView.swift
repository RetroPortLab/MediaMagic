import SwiftUI
import SwiftData

enum SortMode: String, CaseIterable, Identifiable {
    case title = "Title"
    case year = "Year"
    case recentlyAdded = "Recently Added"
    case format = "Format"
    case value = "Value"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]

    @State private var searchText = ""
    @State private var formatFilter: MediaFormat?
    @State private var showWishlist = false
    @State private var sortMode: SortMode = .title

    @State private var newItem: MediaItem?
    @State private var showingSettings = false
    @State private var showingScanner = false
    @State private var scanMatch: MediaItem?
    @State private var path: [MediaItem] = []
    @AppStorage("coverFlowMode") private var coverFlowMode = false

    private var visibleItems: [MediaItem] {
        var items = allItems.filter { $0.isWishlist == showWishlist }
        if let formatFilter { items = items.filter { $0.format == formatFilter } }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items = items.filter { $0.matches(q) } }

        switch sortMode {
        case .title:
            items.sort { sortKey($0.title) < sortKey($1.title) }
        case .year:
            items.sort { ($0.year ?? 0, sortKey($0.title)) > ($1.year ?? 0, sortKey($1.title)) }
        case .recentlyAdded:
            items.sort { $0.dateAdded > $1.dateAdded }
        case .format:
            items.sort { ($0.formatRaw, sortKey($0.title)) < ($1.formatRaw, sortKey($1.title)) }
        case .value:
            items.sort { ($0.estimatedValue ?? -1) > ($1.estimatedValue ?? -1) }
        }
        return items
    }

    /// Sorts "The Thing" under T for "Thing", the way shops shelve them.
    private func sortKey(_ title: String) -> String {
        let lower = title.lowercased()
        for article in ["the ", "a ", "an "] where lower.hasPrefix(article) {
            return String(lower.dropFirst(article.count))
        }
        return lower
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if coverFlowMode && !visibleItems.isEmpty {
                    CoverFlowView(items: visibleItems) { item in path.append(item) }
                } else {
                    List {
                        if searchText.isEmpty {
                            Section {
                                SummaryRow(items: allItems.filter { $0.isWishlist == showWishlist })
                            }
                        }

                        Section {
                            if visibleItems.isEmpty {
                                emptyState
                            } else {
                                ForEach(visibleItems) { item in
                                    NavigationLink(value: item) {
                                        ItemRow(item: item)
                                    }
                                }
                                .onDelete(perform: delete)
                            }
                        }
                    }
                }
            }
            .navigationTitle(showWishlist ? "Wishlist" : "Collection")
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
            .searchable(text: $searchText, prompt: "Title, director, barcode…")
            .safeAreaInset(edge: .top) { filterBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation { coverFlowMode.toggle() }
                    } label: {
                        Image(systemName: coverFlowMode ? "list.bullet" : "square.stack.3d.forward.dottedline")
                    }
                    .accessibilityLabel(coverFlowMode ? "Show as list" : "Show Cover Flow")

                    Menu {
                        Picker("Sort by", selection: $sortMode) {
                            ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")

                    if BarcodeScannerView.isAvailable {
                        Button { showingScanner = true } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .accessibilityLabel("Scan barcode")
                    }

                    Button {
                        let item = MediaItem(format: formatFilter ?? .dvd)
                        item.isWishlist = showWishlist
                        newItem = item
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add item")
                }
            }
            .sheet(item: $newItem) { item in
                NavigationStack {
                    ItemEditView(item: item, isNew: true)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScanSheet { code in
                    showingScanner = false
                    handleScanned(code)
                }
            }
            .alert("Already in your collection",
                   isPresented: Binding(get: { scanMatch != nil },
                                        set: { if !$0 { scanMatch = nil } }),
                   presenting: scanMatch) { item in
                Button("Show it") { path = [item] }
                Button("Add another copy") {
                    let copy = MediaItem(format: item.format, barcode: item.barcode)
                    copy.title = item.title
                    newItem = copy
                }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("\(item.displayTitle) (\(item.subtitle))\(item.isWishlist ? " is on your wishlist." : "")")
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("List", selection: $showWishlist) {
                Text("Owned").tag(false)
                Text("Wishlist").tag(true)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isOn: formatFilter == nil) { formatFilter = nil }
                    ForEach(MediaFormat.allCases) { f in
                        FilterChip(title: f.rawValue, symbol: f.symbol, isOn: formatFilter == f) {
                            formatFilter = (formatFilter == f) ? nil : f
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var emptyState: some View {
        if allItems.isEmpty {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "rectangle.stack")
            } description: {
                Text("Tap + to add something, or scan a barcode.")
            }
        } else {
            ContentUnavailableView.search
        }
    }

    private func delete(at offsets: IndexSet) {
        let items = visibleItems
        for index in offsets { context.delete(items[index]) }
        try? context.save()
    }

    private func handleScanned(_ code: String) {
        if let existing = allItems.first(where: { $0.barcode == code }) {
            scanMatch = existing
        } else {
            let item = MediaItem(format: formatFilter ?? .dvd, barcode: code)
            item.isWishlist = showWishlist
            newItem = item
        }
    }
}

struct FilterChip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct SummaryRow: View {
    let items: [MediaItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                stat("Total", items.count)
                ForEach(MediaFormat.allCases) { f in
                    let count = items.filter { $0.format == f }.count
                    if count > 0 { stat(f.rawValue, count) }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 48)
    }
}

struct ItemRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            CoverThumbnail(item: item, width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).font(.body.weight(.medium)).lineLimit(2)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !item.location.isEmpty {
                    Label(item.location, systemImage: "shippingbox")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if let value = item.formattedValue {
                    Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if item.rating > 0 {
                    Text(String(repeating: "★", count: item.rating))
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct CoverThumbnail: View {
    let item: MediaItem
    let width: CGFloat

    var body: some View {
        let height = width * item.format.coverAspect
        Group {
            if let data = item.coverImage, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: item.format.symbol).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
