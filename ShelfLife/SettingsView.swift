import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [MediaItem]

    @State private var excludeFromBackup = BackupExclusion.isExcluded
    @State private var lookupEnabled = LookupSettings.isEnabled
    @State private var discogsToken = LookupSettings.discogsToken
    @State private var omdbKey = LookupSettings.omdbKey
    @State private var priceChartingToken = LookupSettings.priceChartingToken
    @State private var exportDoc: ExportDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = ""
    @State private var showingImporter = false
    @State private var message: String?

    private var owned: [MediaItem] { items.filter { !$0.isWishlist } }

    private var totalSpent: Double {
        owned.compactMap(\.purchasePrice).reduce(0, +)
    }

    /// Values can come back in different currencies, so they're totalled separately.
    private var valueTotals: [(currency: String, total: Double, count: Int)] {
        var sums: [String: (Double, Int)] = [:]
        for item in owned {
            guard let v = item.estimatedValue else { continue }
            let code = item.valueCurrency.isEmpty ? "USD" : item.valueCurrency
            let current = sums[code] ?? (0, 0)
            sums[code] = (current.0 + v, current.1 + 1)
        }
        return sums.map { (currency: $0.key, total: $0.value.0, count: $0.value.1) }.sorted { $0.currency < $1.currency }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Collection") {
                    LabeledContent("Owned", value: "\(owned.count)")
                    LabeledContent("Wishlist", value: "\(items.count - owned.count)")
                    ForEach(MediaFormat.allCases) { f in
                        LabeledContent(f.rawValue, value: "\(owned.filter { $0.format == f }.count)")
                    }
                    if totalSpent > 0 {
                        LabeledContent("Total paid",
                                       value: totalSpent.formatted(.currency(code: Locale.current.currency?.identifier ?? "GBP")))
                    }
                    ForEach(valueTotals, id: \.currency) { t in
                        LabeledContent("Est. value (\(t.count) valued, \(t.currency))",
                                       value: t.total.formatted(.currency(code: t.currency)))
                    }
                }

                Section {
                    Toggle("Online barcode lookup", isOn: $lookupEnabled)
                        .onChange(of: lookupEnabled) { _, v in LookupSettings.isEnabled = v }
                    if lookupEnabled {
                        keyField("Discogs token", text: $discogsToken,
                                 link: "https://www.discogs.com/settings/developers") {
                            LookupSettings.discogsToken = $0
                        }
                        keyField("OMDb API key", text: $omdbKey,
                                 link: "https://www.omdbapi.com/apikey.aspx") {
                            LookupSettings.omdbKey = $0
                        }
                        keyField("PriceCharting token", text: $priceChartingToken,
                                 link: "https://www.pricecharting.com/api-documentation") {
                            LookupSettings.priceChartingToken = $0
                        }
                    }
                } header: {
                    Text("Online lookup")
                } footer: {
                    Text("""
                    Only used when you scan or tap “Look up”. Just the barcode (and for films, the title) is sent. Your catalogue itself never leaves the phone.

                    Works without keys using UPCitemdb (≈100 lookups a day, US shop prices) and MusicBrainz (music details). Optional keys add:
                    • Discogs (free) — vinyl & CD details and current lowest selling price
                    • OMDb (free) — film director, cast, plot, poster
                    • PriceCharting (paid subscription) — retro game values
                    Keys are stored in the Keychain on this device only.
                    """)
                }

                Section {
                    Toggle("Keep out of iCloud Backup", isOn: $excludeFromBackup)
                        .onChange(of: excludeFromBackup) { _, value in
                            BackupExclusion.isExcluded = value
                        }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Your catalogue is stored only on this phone. With this on, it isn't even included in your iCloud backup — so export a backup file below now and then and keep it somewhere safe (a computer, a USB stick).")
                }

                Section {
                    Button {
                        export(json: true)
                    } label: {
                        Label("Export full backup (.json)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        export(json: false)
                    } label: {
                        Label("Export spreadsheet (.csv)", systemImage: "tablecells")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Restore from backup (.json)", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Files are saved wherever you choose — pick “On My iPhone” to keep them local. The JSON backup includes cover photos; the CSV is for spreadsheets. Restoring adds missing items and never deletes anything.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
            .fileExporter(isPresented: Binding(get: { exportDoc != nil },
                                               set: { if !$0 { exportDoc = nil } }),
                          document: exportDoc,
                          contentType: exportType,
                          defaultFilename: exportName) { result in
                if case .failure(let error) = result {
                    message = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): importBackup(from: url)
                case .failure(let error): message = "Couldn't open file: \(error.localizedDescription)"
                }
            }
            .alert("ShelfLife", isPresented: Binding(get: { message != nil },
                                                    set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func keyField(_ label: String, text: Binding<String>, link: String,
                          save: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField(label, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { _, v in save(v) }
            if text.wrappedValue.isEmpty, let url = URL(string: link) {
                Link("Get a key", destination: url).font(.caption)
            }
        }
    }

    private func export(json: Bool) {
        let stamp = Date().formatted(.iso8601.year().month().day())
        do {
            if json {
                exportDoc = ExportDocument(data: try BackupCodec.encode(items))
                exportType = .json
                exportName = "ShelfLife-backup-\(stamp)"
            } else {
                exportDoc = ExportDocument(data: BackupCodec.csv(items))
                exportType = .commaSeparatedText
                exportName = "ShelfLife-\(stamp)"
            }
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let records = try BackupCodec.decode(data)
            let existing = Set(items.map(\.id))
            var added = 0
            for record in records where !existing.contains(record.id) {
                context.insert(record.makeItem())
                added += 1
            }
            try context.save()
            message = "Restored \(added) item\(added == 1 ? "" : "s"). \(records.count - added) already present."
        } catch {
            message = "That file couldn't be read as a ShelfLife backup."
        }
    }
}

// MARK: - File plumbing

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Plain, versioned record used for backups so the file format is stable and readable.
struct ItemRecord: Codable {
    var id: UUID
    var title: String
    var format: String
    var year: Int?
    var director: String
    var cast: String
    var genre: String
    var studio: String
    var edition: String
    var region: String
    var videoStandard: String
    var aspectRatio: String
    var runtimeMinutes: Int?
    var discCount: Int
    var laserDiscType: String
    var platform: String?
    var vinylSize: String?
    var vinylSpeed: String?
    var barcode: String
    var catalogNumber: String
    var condition: String
    var isSealed: Bool
    var location: String
    var purchasePrice: Double?
    var purchaseDate: Date?
    var purchasedFrom: String
    var rating: Int
    var summary: String?
    var notes: String
    var isWishlist: Bool
    var coverImage: Data?
    var estimatedValue: Double?
    var valueLow: Double?
    var valueHigh: Double?
    var valueCurrency: String?
    var valueSource: String?
    var valueUpdated: Date?
    var dateAdded: Date

    init(_ i: MediaItem) {
        id = i.id; title = i.title; format = i.formatRaw; year = i.year
        director = i.director; cast = i.cast; genre = i.genre; studio = i.studio
        edition = i.edition; region = i.region; videoStandard = i.videoStandardRaw
        aspectRatio = i.aspectRatio; runtimeMinutes = i.runtimeMinutes
        discCount = i.discCount; laserDiscType = i.laserDiscTypeRaw; barcode = i.barcode
        catalogNumber = i.catalogNumber; condition = i.conditionRaw; isSealed = i.isSealed
        location = i.location; purchasePrice = i.purchasePrice; purchaseDate = i.purchaseDate
        purchasedFrom = i.purchasedFrom; rating = i.rating; notes = i.notes
        isWishlist = i.isWishlist; coverImage = i.coverImage; dateAdded = i.dateAdded
        platform = i.platform; vinylSize = i.vinylSize; vinylSpeed = i.vinylSpeed
        summary = i.summary; estimatedValue = i.estimatedValue; valueLow = i.valueLow
        valueHigh = i.valueHigh; valueCurrency = i.valueCurrency; valueSource = i.valueSource
        valueUpdated = i.valueUpdated
    }

    func makeItem() -> MediaItem {
        let i = MediaItem(title: title, format: MediaFormat(rawValue: format) ?? .dvd, barcode: barcode)
        i.id = id; i.year = year; i.director = director; i.cast = cast; i.genre = genre
        i.studio = studio; i.edition = edition; i.region = region
        i.videoStandardRaw = videoStandard; i.aspectRatio = aspectRatio
        i.runtimeMinutes = runtimeMinutes; i.discCount = discCount
        i.laserDiscTypeRaw = laserDiscType; i.catalogNumber = catalogNumber
        i.conditionRaw = condition; i.isSealed = isSealed; i.location = location
        i.purchasePrice = purchasePrice; i.purchaseDate = purchaseDate
        i.purchasedFrom = purchasedFrom; i.rating = rating; i.notes = notes
        i.isWishlist = isWishlist; i.coverImage = coverImage; i.dateAdded = dateAdded
        i.platform = platform ?? ""; i.vinylSize = vinylSize ?? ""; i.vinylSpeed = vinylSpeed ?? ""
        i.summary = summary ?? ""; i.estimatedValue = estimatedValue; i.valueLow = valueLow
        i.valueHigh = valueHigh; i.valueCurrency = valueCurrency ?? ""
        i.valueSource = valueSource ?? ""; i.valueUpdated = valueUpdated
        return i
    }
}

struct BackupFile: Codable {
    var app = "ShelfLife"
    var version = 1
    var exported = Date()
    var items: [ItemRecord]
}

enum BackupCodec {
    static func encode(_ items: [MediaItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(BackupFile(items: items.map(ItemRecord.init)))
    }

    static func decode(_ data: Data) throws -> [ItemRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data).items
    }

    static func csv(_ items: [MediaItem]) -> Data {
        let header = ["Title", "Format", "Year", "Director", "Cast", "Genre", "Studio",
                      "Edition", "Region", "Video Standard", "Aspect Ratio", "Runtime",
                      "Discs/Tapes", "LaserDisc Type", "Platform", "Vinyl Size", "Vinyl Speed", "Barcode", "Catalogue No.",
                      "Condition", "Sealed", "Location", "Price Paid", "Purchase Date",
                      "Bought From", "Rating", "Estimated Value", "Value Currency", "Value Source",
                      "Wishlist", "Summary", "Notes", "Date Added"]
        let date: (Date?) -> String = { $0?.formatted(.iso8601.year().month().day()) ?? "" }
        var lines = [header.map(escape).joined(separator: ",")]
        for i in items.sorted(by: { $0.title.lowercased() < $1.title.lowercased() }) {
            let row: [String] = [
                i.title, i.formatRaw, i.year.map(String.init) ?? "", i.director, i.cast,
                i.genre, i.studio, i.edition, i.region, i.videoStandardRaw, i.aspectRatio,
                i.runtimeMinutes.map(String.init) ?? "", String(i.discCount),
                i.laserDiscTypeRaw, i.platform, i.vinylSize, i.vinylSpeed, i.barcode, i.catalogNumber, i.conditionRaw,
                i.isSealed ? "Yes" : "", i.location,
                i.purchasePrice.map { String(format: "%.2f", $0) } ?? "",
                date(i.purchaseDate), i.purchasedFrom, i.rating > 0 ? String(i.rating) : "",
                i.estimatedValue.map { String(format: "%.2f", $0) } ?? "", i.valueCurrency, i.valueSource,
                i.isWishlist ? "Yes" : "", i.summary, i.notes, date(i.dateAdded)
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        // BOM so Excel opens accented titles correctly.
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n")).utf8)
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
