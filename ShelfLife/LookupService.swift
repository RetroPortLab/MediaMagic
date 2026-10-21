import Foundation
import Security

// MARK: - Settings & keys

/// Online lookup is the only thing in the app that touches the network.
/// It sends just the barcode (and, for films, the title) to the services below.
enum LookupSettings {
    private static let enabledKey = "onlineLookupEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var discogsToken: String {
        get { Keychain.get("discogsToken") }
        set { Keychain.set(newValue, for: "discogsToken") }
    }
    static var omdbKey: String {
        get { Keychain.get("omdbKey") }
        set { Keychain.set(newValue, for: "omdbKey") }
    }
    static var priceChartingToken: String {
        get { Keychain.get("priceChartingToken") }
        set { Keychain.set(newValue, for: "priceChartingToken") }
    }

    /// Currency for Discogs prices — your phone's currency if Discogs supports it.
    static var preferredCurrency: String {
        let supported = ["USD", "GBP", "EUR", "CAD", "AUD", "JPY", "CHF", "MXN", "BRL", "NZD", "SEK", "ZAR"]
        let local = Locale.current.currency?.identifier ?? "GBP"
        return supported.contains(local) ? local : "GBP"
    }
}

/// API keys live in the Keychain, marked this-device-only so they never sync to iCloud Keychain.
enum Keychain {
    private static let service = "ShelfLife.lookup"

    static func get(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Result

struct LookupResult {
    var title: String?
    var format: MediaFormat?
    var year: Int?
    var creator: String?
    var cast: String?
    var genre: String?
    var studio: String?
    var platform: String?
    var videoStandard: VideoStandard?
    var runtimeMinutes: Int?
    var catalogNumber: String?
    var region: String?
    var vinylSize: String?
    var vinylSpeed: String?
    var summary: String?
    var coverURL: URL?
    var coverData: Data?

    var value: Double?
    var valueLow: Double?
    var valueHigh: Double?
    var valueCurrency: String?
    var valueSource: String?

    var sources: [String] = []

    var isEmpty: Bool { title == nil && value == nil }

    /// Keeps what we already have and fills the gaps from a lower-priority source.
    mutating func fillMissing(from o: LookupResult) {
        title = title ?? o.title
        format = format ?? o.format
        year = year ?? o.year
        creator = creator ?? o.creator
        cast = cast ?? o.cast
        genre = genre ?? o.genre
        studio = studio ?? o.studio
        platform = platform ?? o.platform
        videoStandard = videoStandard ?? o.videoStandard
        runtimeMinutes = runtimeMinutes ?? o.runtimeMinutes
        catalogNumber = catalogNumber ?? o.catalogNumber
        region = region ?? o.region
        vinylSize = vinylSize ?? o.vinylSize
        vinylSpeed = vinylSpeed ?? o.vinylSpeed
        summary = summary ?? o.summary
        coverURL = coverURL ?? o.coverURL
        if value == nil, o.value != nil {
            value = o.value; valueLow = o.valueLow; valueHigh = o.valueHigh
            valueCurrency = o.valueCurrency; valueSource = o.valueSource
        }
        for s in o.sources where !sources.contains(s) { sources.append(s) }
    }
}

struct LookupOutcome {
    var result: LookupResult
    var problems: [String]

    var summaryText: String {
        var lines: [String] = []
        if result.isEmpty {
            lines.append("No match found online.")
        } else {
            lines.append("Filled in from \(result.sources.joined(separator: ", ")).")
        }
        lines.append(contentsOf: problems)
        return lines.joined(separator: "\n")
    }
}

enum LookupError: LocalizedError {
    case rateLimited, notFound, badResponse, http(Int)
    var errorDescription: String? {
        switch self {
        case .rateLimited: return "daily or per-minute limit reached, try later"
        case .notFound: return "not found"
        case .badResponse: return "unexpected response"
        case .http(let code): return "server error \(code)"
        }
    }
}

// MARK: - Service

@MainActor
final class LookupService {
    static let shared = LookupService()

    private let session: URLSession = {
        // Ephemeral: no cookies or cache written to disk.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private let userAgent = "ShelfLife/1.0 (personal collection app)"

    /// Looks up a barcode across the free/keyed services and merges what comes back.
    /// - Parameter formatHint: the format currently chosen in the form, used when the
    ///   services can't tell what kind of item it is.
    func lookup(barcode rawCode: String, formatHint: MediaFormat?, includeCover: Bool = true) async -> LookupOutcome {
        let code = rawCode.filter(\.isNumber)
        var problems: [String] = []
        guard !code.isEmpty else {
            return LookupOutcome(result: LookupResult(), problems: ["That barcode has no digits to look up."])
        }

        let discogsToken = LookupSettings.discogsToken
        let omdbKey = LookupSettings.omdbKey
        let pcToken = LookupSettings.priceChartingToken

        // First wave in parallel: the general UPC database plus any keyed services.
        async let upcTask = capture { () async throws -> LookupResult? in
            try await self.upcItemDB(code)
        }
        async let discogsTask = capture { () async throws -> LookupResult? in
            if discogsToken.isEmpty { return nil }
            return try await self.discogs(code, token: discogsToken)
        }
        async let pcTask = capture { () async throws -> LookupResult? in
            if pcToken.isEmpty { return nil }
            return try await self.priceCharting(code, token: pcToken)
        }

        let (upc, upcErr) = await upcTask
        let (discogs, discogsErr) = await discogsTask
        let (pc, pcErr) = await pcTask
        if let upcErr { problems.append("UPCitemdb: \(upcErr)") }
        if let discogsErr { problems.append("Discogs: \(discogsErr)") }
        if let pcErr { problems.append("PriceCharting: \(pcErr)") }

        let format = discogs?.format ?? (pc != nil ? .game : nil) ?? upc?.format ?? formatHint
        var result = LookupResult()
        let kind = format?.kind ?? (discogs != nil ? MediaFormat.Kind.music : nil)

        switch kind {
        case .music?:
            if let discogs { result.fillMissing(from: discogs) }
            if discogs == nil {
                let (mb, mbErr) = await capture { () async throws -> LookupResult? in
                    try await self.musicBrainz(code)
                }
                if let mb { result.fillMissing(from: mb) }
                if let mbErr { problems.append("MusicBrainz: \(mbErr)") }
            }
            if let upc { result.fillMissing(from: upc) }

        case .game?:
            if let pc { result.fillMissing(from: pc) }
            if let upc { result.fillMissing(from: upc) }

        default: // video, or unknown
            if let upc { result.fillMissing(from: upc) }
            if let title = result.title, !omdbKey.isEmpty, format == nil || format?.kind == .video {
                let (film, filmErr) = await capture { () async throws -> LookupResult? in
                    try await self.omdb(title: title, key: omdbKey)
                }
                if let film {
                    // OMDb's cleaner title and film details take priority over the shop listing.
                    var merged = film
                    merged.fillMissing(from: result)
                    merged.format = result.format ?? formatHint
                    result = merged
                }
                if let filmErr { problems.append("OMDb: \(filmErr)") }
            }
            if result.title == nil {
                // Nothing in the UPC database — it may be music not tagged as such.
                let (mb, _) = await capture { () async throws -> LookupResult? in
                    try await self.musicBrainz(code)
                }
                if let mb { result.fillMissing(from: mb) }
            }
        }

        if result.format == nil { result.format = format }

        if includeCover, let url = result.coverURL {
            result.coverData = await downloadImage(url)
        }
        return LookupOutcome(result: result, problems: problems)
    }

    // MARK: Helpers

    private func capture<T>(_ work: () async throws -> T?) async -> (T?, String?) {
        do { return (try await work(), nil) }
        catch LookupError.notFound { return (nil, nil) }
        catch let e as LookupError { return (nil, e.errorDescription) }
        catch let e as URLError where e.code == .notConnectedToInternet { return (nil, "no internet connection") }
        catch { return (nil, error.localizedDescription) }
    }

    private func get<T: Decodable>(_ url: URL, _ type: T.Type, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LookupError.badResponse }
        switch http.statusCode {
        case 200..<300: break
        case 404: throw LookupError.notFound
        case 429: throw LookupError.rateLimited
        default: throw LookupError.http(http.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw LookupError.badResponse }
    }

    private func url(_ base: String, _ query: [String: String]) -> URL? {
        var c = URLComponents(string: base)
        c?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c?.url
    }

    private func downloadImage(_ url: URL) async -> Data? {
        // Many shop listings use plain http, which iOS blocks; try the https version.
        var candidate = url
        if url.scheme == "http", var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.scheme = "https"
            candidate = c.url ?? url
        }
        var request = URLRequest(url: candidate)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let fetched = try? await session.data(for: request),
              let http = fetched.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return ImageTools.compressedCover(from: fetched.0)
    }

    // MARK: UPCitemdb — free, no key, ~100 lookups/day

    private struct UPCResponse: Decodable { let items: [UPCItem]? }
    private struct UPCItem: Decodable {
        let title: String?
        let description: String?
        let brand: String?
        let category: String?
        let images: [String]?
        let lowestRecordedPrice: Double?
        let highestRecordedPrice: Double?
        let offers: [UPCOffer]?
        enum CodingKeys: String, CodingKey {
            case title, description, brand, category, images, offers
            case lowestRecordedPrice = "lowest_recorded_price"
            case highestRecordedPrice = "highest_recorded_price"
        }
    }
    private struct UPCOffer: Decodable { let price: Double? }

    private func upcItemDB(_ code: String) async throws -> LookupResult? {
        guard let u = url("https://api.upcitemdb.com/prod/trial/lookup", ["upc": code]) else { return nil }
        let response = try await get(u, UPCResponse.self)
        guard let item = response.items?.first, let rawTitle = item.title, !rawTitle.isEmpty else { return nil }

        let text = [rawTitle, item.category ?? "", item.description ?? ""].joined(separator: " ")
        var r = LookupResult()
        r.format = Infer.format(from: text)
        r.title = r.format == .game || r.format?.kind == .video ? Infer.cleanTitle(rawTitle) : rawTitle
        r.studio = item.brand.flatMap { $0.isEmpty ? nil : $0 }
        r.platform = r.format == .game ? Infer.platform(from: text) : nil
        r.videoStandard = Infer.standard(from: text)
        r.year = Infer.year(from: rawTitle)
        r.coverURL = item.images?.compactMap(URL.init(string:)).first

        let prices = (item.offers ?? []).compactMap(\.price).filter { $0 > 0 }.sorted()
        if !prices.isEmpty {
            r.value = prices[prices.count / 2]
            r.valueLow = prices.first; r.valueHigh = prices.last
        } else if let lo = item.lowestRecordedPrice, let hi = item.highestRecordedPrice, hi > 0 {
            r.value = (lo + hi) / 2; r.valueLow = lo; r.valueHigh = hi
        }
        if r.value != nil {
            r.valueCurrency = "USD"
            r.valueSource = "UPCitemdb shop listings"
        }
        r.sources = ["UPCitemdb"]
        return r
    }

    // MARK: Discogs — free personal token; vinyl, CD, music video, LaserDisc

    private struct DiscogsSearch: Decodable { let results: [DiscogsRelease]? }
    private struct DiscogsRelease: Decodable {
        let id: Int
        let title: String?
        let year: String?
        let country: String?
        let format: [String]?
        let label: [String]?
        let genre: [String]?
        let style: [String]?
        let catno: String?
        let coverImage: String?
        enum CodingKeys: String, CodingKey {
            case id, title, year, country, format, label, genre, style, catno
            case coverImage = "cover_image"
        }
    }
    private struct DiscogsStats: Decodable {
        let lowestPrice: DiscogsPrice?
        let numForSale: Int?
        enum CodingKeys: String, CodingKey {
            case lowestPrice = "lowest_price"
            case numForSale = "num_for_sale"
        }
    }
    private struct DiscogsPrice: Decodable { let currency: String; let value: Double }

    private func discogs(_ code: String, token: String) async throws -> LookupResult? {
        let auth = ["Authorization": "Discogs token=\(token)"]
        guard let u = url("https://api.discogs.com/database/search", ["barcode": code, "type": "release"]) else { return nil }
        let search = try await get(u, DiscogsSearch.self, headers: auth)
        guard let rel = search.results?.first else { return nil }

        var r = LookupResult()
        if let full = rel.title {
            // Discogs titles are "Artist - Title".
            if let range = full.range(of: " - ") {
                r.creator = String(full[..<range.lowerBound]).replacingOccurrences(of: #" \(\d+\)"#, with: "", options: .regularExpression)
                r.title = String(full[range.upperBound...])
            } else {
                r.title = full
            }
        }
        let formats = (rel.format ?? []).map { $0.lowercased() }
        if formats.contains("vinyl") { r.format = .vinyl }
        else if formats.contains("cd") || formats.contains("cdr") { r.format = .cd }
        else if formats.contains("laserdisc") { r.format = .laserDisc }
        else if formats.contains("vhs") { r.format = .vhs }
        else if formats.contains("dvd") || formats.contains("dvd-video") { r.format = .dvd }

        if r.format == .vinyl {
            if formats.contains("7\"") { r.vinylSize = "7\"" }
            else if formats.contains("10\"") { r.vinylSize = "10\"" }
            else if formats.contains("12\"") || formats.contains("lp") { r.vinylSize = "12\"" }
            if formats.contains(where: { $0.contains("45 rpm") }) { r.vinylSpeed = "45" }
            else if formats.contains(where: { $0.contains("78 rpm") }) { r.vinylSpeed = "78" }
            else if formats.contains(where: { $0.contains("33") }) || formats.contains("lp") { r.vinylSpeed = "33⅓" }
        }
        r.year = rel.year.flatMap(Int.init)
        r.studio = rel.label?.first
        r.catalogNumber = rel.catno.flatMap { $0 == "none" ? nil : $0 }
        r.region = rel.country
        r.genre = ((rel.genre ?? []) + (rel.style ?? [])).prefix(3).joined(separator: ", ").nilIfEmpty
        r.coverURL = rel.coverImage.flatMap(URL.init(string:))
        r.sources = ["Discogs"]

        let currency = LookupSettings.preferredCurrency
        if let su = url("https://api.discogs.com/marketplace/stats/\(rel.id)", ["curr_abbr": currency]),
           let stats = try? await get(su, DiscogsStats.self, headers: auth),
           let lowest = stats.lowestPrice {
            r.value = lowest.value
            r.valueLow = lowest.value
            r.valueCurrency = lowest.currency
            let count = stats.numForSale ?? 0
            r.valueSource = "Discogs lowest of \(count) for sale"
        }
        return r
    }

    // MARK: MusicBrainz — free, no key; details only, no prices

    private struct MBSearch: Decodable { let releases: [MBRelease]? }
    private struct MBRelease: Decodable {
        let id: String
        let title: String?
        let date: String?
        let country: String?
        let artistCredit: [MBCredit]?
        let labelInfo: [MBLabelInfo]?
        let media: [MBMedia]?
        enum CodingKeys: String, CodingKey {
            case id, title, date, country, media
            case artistCredit = "artist-credit"
            case labelInfo = "label-info"
        }
    }
    private struct MBCredit: Decodable { let name: String?; let joinphrase: String? }
    private struct MBLabelInfo: Decodable {
        let catalogNumber: String?
        let label: MBLabel?
        enum CodingKeys: String, CodingKey { case label; case catalogNumber = "catalog-number" }
    }
    private struct MBLabel: Decodable { let name: String? }
    private struct MBMedia: Decodable { let format: String? }

    private func musicBrainz(_ code: String) async throws -> LookupResult? {
        guard let u = url("https://musicbrainz.org/ws/2/release/", ["query": "barcode:\(code)", "fmt": "json", "limit": "1"]) else { return nil }
        let search = try await get(u, MBSearch.self)
        guard let rel = search.releases?.first else { return nil }

        var r = LookupResult()
        r.title = rel.title
        r.creator = rel.artistCredit?.map { ($0.name ?? "") + ($0.joinphrase ?? "") }.joined().nilIfEmpty
        r.year = rel.date.flatMap { Int($0.prefix(4)) }
        r.region = rel.country
        r.studio = rel.labelInfo?.first?.label?.name
        r.catalogNumber = rel.labelInfo?.first?.catalogNumber
        let mediaFormat = (rel.media?.first?.format ?? "").lowercased()
        if mediaFormat.contains("vinyl") {
            r.format = .vinyl
            for size in ["7\"", "10\"", "12\""] where mediaFormat.contains(size) { r.vinylSize = size }
        } else if mediaFormat.contains("cd") {
            r.format = .cd
        } else if mediaFormat.contains("laserdisc") {
            r.format = .laserDisc
        }
        r.coverURL = URL(string: "https://coverartarchive.org/release/\(rel.id)/front-500")
        r.sources = ["MusicBrainz"]
        return r
    }

    // MARK: OMDb — free key, 1,000/day; film details by title

    private struct OMDbFilm: Decodable {
        let title: String?
        let year: String?
        let runtime: String?
        let genre: String?
        let director: String?
        let actors: String?
        let plot: String?
        let poster: String?
        let response: String?
        enum CodingKeys: String, CodingKey {
            case title = "Title", year = "Year", runtime = "Runtime", genre = "Genre"
            case director = "Director", actors = "Actors", plot = "Plot"
            case poster = "Poster", response = "Response"
        }
    }

    private func omdb(title: String, key: String) async throws -> LookupResult? {
        guard let u = url("https://www.omdbapi.com/", ["apikey": key, "t": title, "type": "movie", "plot": "short"]) else { return nil }
        let film = try await get(u, OMDbFilm.self)
        guard film.response == "True" else { return nil }
        func clean(_ s: String?) -> String? { (s == nil || s == "N/A") ? nil : s }

        var r = LookupResult()
        r.title = clean(film.title)
        r.year = clean(film.year).flatMap { Int($0.prefix(4)) }
        r.runtimeMinutes = clean(film.runtime).flatMap { Int($0.filter(\.isNumber)) }
        r.genre = clean(film.genre)
        r.creator = clean(film.director)
        r.cast = clean(film.actors)
        r.summary = clean(film.plot)
        r.coverURL = clean(film.poster).flatMap(URL.init(string:))
        r.sources = ["OMDb"]
        return r
    }

    // MARK: PriceCharting — paid token; video game values by UPC

    private struct PCProduct: Decodable {
        let status: String?
        let productName: String?
        let consoleName: String?
        let loosePrice: Int?
        let cibPrice: Int?
        let newPrice: Int?
        let releaseDate: String?
        let genre: String?
        enum CodingKeys: String, CodingKey {
            case status, genre
            case productName = "product-name"
            case consoleName = "console-name"
            case loosePrice = "loose-price"
            case cibPrice = "cib-price"
            case newPrice = "new-price"
            case releaseDate = "release-date"
        }
    }

    private func priceCharting(_ code: String, token: String) async throws -> LookupResult? {
        guard let u = url("https://www.pricecharting.com/api/product", ["t": token, "upc": code]) else { return nil }
        let p = try await get(u, PCProduct.self)
        guard p.status == "success", let name = p.productName else { return nil }

        var r = LookupResult()
        r.title = name
        r.format = .game
        if var console = p.consoleName {
            if console.hasPrefix("PAL ") { r.videoStandard = .pal; console.removeFirst(4) }
            else if console.hasPrefix("JP ") { r.videoStandard = .ntsc; r.region = "Japan"; console.removeFirst(3) }
            r.platform = console
        }
        r.year = p.releaseDate.flatMap { Int($0.prefix(4)) }
        r.genre = p.genre
        let dollars: (Int?) -> Double? = { $0.flatMap { $0 > 0 ? Double($0) / 100 : nil } }
        r.valueLow = dollars(p.loosePrice)
        r.valueHigh = dollars(p.newPrice)
        r.value = dollars(p.cibPrice) ?? r.valueLow
        if r.value != nil {
            r.valueCurrency = "USD"
            r.valueSource = "PriceCharting (complete in box; range loose–new)"
        }
        r.sources = ["PriceCharting"]
        return r
    }
}

// MARK: - Guessing from shop listing text

enum Infer {
    static func format(from text: String) -> MediaFormat? {
        let t = text.lowercased()
        if t.contains("laserdisc") || t.contains("laser disc") { return .laserDisc }
        if t.contains("vhs") || t.contains("videocassette") || t.contains("video cassette") { return .vhs }
        if t.contains("vinyl") || t.contains(" lp ") || t.hasSuffix(" lp") || t.contains("12\"") || t.contains("7\" single") { return .vinyl }
        if platform(from: t) != nil || t.contains("video game") { return .game }
        if t.contains("dvd") { return .dvd }
        if t.contains("audio cd") || t.contains("compact disc") || t.contains("music cd")
            || (t.contains(" cd") && t.contains("music")) { return .cd }
        return nil
    }

    private static let platforms: [(String, String)] = [
        ("playstation 5", "PlayStation 5"), ("ps5", "PlayStation 5"),
        ("playstation 4", "PlayStation 4"), ("ps4", "PlayStation 4"),
        ("playstation 3", "PlayStation 3"), ("ps3", "PlayStation 3"),
        ("playstation 2", "PlayStation 2"), ("ps2", "PlayStation 2"),
        ("playstation vita", "PS Vita"), ("psp", "PSP"),
        ("playstation", "PlayStation"),
        ("xbox series", "Xbox Series X|S"), ("xbox one", "Xbox One"),
        ("xbox 360", "Xbox 360"), ("xbox", "Xbox"),
        ("nintendo switch", "Nintendo Switch"), ("wii u", "Wii U"), ("wii", "Wii"),
        ("gamecube", "GameCube"), ("nintendo 64", "Nintendo 64"), ("n64", "Nintendo 64"),
        ("super nintendo", "SNES"), ("snes", "SNES"),
        ("nintendo 3ds", "Nintendo 3DS"), ("3ds", "Nintendo 3DS"), ("nintendo ds", "Nintendo DS"),
        ("game boy advance", "Game Boy Advance"), ("game boy color", "Game Boy Color"),
        ("game boy", "Game Boy"),
        ("dreamcast", "Dreamcast"), ("sega saturn", "Saturn"),
        ("mega drive", "Mega Drive"), ("genesis", "Mega Drive / Genesis"),
        ("master system", "Master System"), ("game gear", "Game Gear"),
        ("vectrex", "Vectrex"), ("atari 2600", "Atari 2600"), ("atari jaguar", "Atari Jaguar")
    ]

    static func platform(from text: String) -> String? {
        let t = text.lowercased()
        return platforms.first { t.contains($0.0) }?.1
    }

    static func standard(from text: String) -> VideoStandard? {
        let t = " " + text.lowercased() + " "
        if t.contains(" pal ") || t.contains("(pal)") || t.contains("pal version") { return .pal }
        if t.contains(" ntsc ") || t.contains("(ntsc)") { return .ntsc }
        return nil
    }

    static func year(from text: String) -> Int? {
        guard let range = text.range(of: #"\b(19[2-9]\d|20[0-4]\d)\b"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    /// "Aliens (DVD, 2003, Special Edition) [Region 2]" → "Aliens"
    static func cleanTitle(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
        let noise = #"\b(dvd|vhs|blu-?ray|laserdisc|widescreen|full ?screen|special edition|collector'?s edition|region \d|pal|ntsc|video game|for (playstation|xbox|nintendo|wii|ps\d)[\w\s]*)\b"#
        t = t.replacingOccurrences(of: noise, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " -–:,"))
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
