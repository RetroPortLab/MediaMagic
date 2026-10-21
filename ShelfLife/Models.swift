import Foundation
import CoreGraphics
import SwiftData

enum MediaFormat: String, Codable, CaseIterable, Identifiable {
    case dvd = "DVD"
    case vhs = "VHS"
    case laserDisc = "LaserDisc"
    case vinyl = "Vinyl"
    case cd = "CD"
    case game = "Game"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dvd: return "opticaldisc"
        case .vhs: return "film"
        case .laserDisc: return "circle.circle"
        case .vinyl: return "record.circle"
        case .cd: return "music.note"
        case .game: return "gamecontroller"
        }
    }

    enum Kind { case video, music, game }

    var kind: Kind {
        switch self {
        case .dvd, .vhs, .laserDisc: return .video
        case .vinyl, .cd: return .music
        case .game: return .game
        }
    }

    /// What a single physical unit is called for this format.
    var unitName: String {
        switch self {
        case .vhs: return "Tapes"
        case .vinyl: return "Records"
        case .game: return "Discs / Carts"
        case .dvd, .laserDisc, .cd: return "Discs"
        }
    }

    var creatorLabel: String {
        switch kind {
        case .video: return "Director"
        case .music: return "Artist"
        case .game: return "Developer"
        }
    }

    var studioLabel: String {
        switch kind {
        case .video: return "Studio / Label"
        case .music: return "Record label"
        case .game: return "Publisher"
        }
    }

    var showsVideoStandard: Bool { kind != .music }

    /// Covers: DVD/VHS/game cases are roughly 7:10; records, CDs and LaserDiscs are square.
    var coverAspect: CGFloat {
        switch self {
        case .laserDisc, .vinyl, .cd: return 1
        default: return 1.4
        }
    }
}

enum VideoStandard: String, Codable, CaseIterable, Identifiable {
    case unknown = ""
    case pal = "PAL"
    case ntsc = "NTSC"
    case secam = "SECAM"

    var id: String { rawValue }
    var label: String { self == .unknown ? "Not set" : rawValue }
}

enum ItemCondition: String, Codable, CaseIterable, Identifiable {
    case unknown = ""
    case mint = "Mint"
    case nearMint = "Near Mint"
    case veryGood = "Very Good"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var id: String { rawValue }
    var label: String { self == .unknown ? "Not set" : rawValue }
}

enum LaserDiscType: String, Codable, CaseIterable, Identifiable {
    case unknown = ""
    case cav = "CAV"
    case clv = "CLV"
    case extendedPlay = "CLV Extended Play"
    case mixed = "CAV/CLV Mixed"

    var id: String { rawValue }
    var label: String { self == .unknown ? "Not set" : rawValue }
}

@Model
final class MediaItem {
    var id: UUID = UUID()
    var title: String = ""
    var formatRaw: String = MediaFormat.dvd.rawValue
    var year: Int?
    /// Director, artist or developer depending on format.
    var director: String = ""
    var cast: String = ""
    var genre: String = ""
    /// Studio, record label or publisher depending on format.
    var studio: String = ""
    var edition: String = ""
    var region: String = ""
    var videoStandardRaw: String = ""
    var aspectRatio: String = ""
    var runtimeMinutes: Int?
    var discCount: Int = 1
    var laserDiscTypeRaw: String = ""
    var platform: String = ""
    var vinylSize: String = ""
    var vinylSpeed: String = ""
    var barcode: String = ""
    var catalogNumber: String = ""
    var conditionRaw: String = ""
    var isSealed: Bool = false
    var location: String = ""
    var purchasePrice: Double?
    var purchaseDate: Date?
    var purchasedFrom: String = ""
    var rating: Int = 0
    var summary: String = ""
    var notes: String = ""
    var isWishlist: Bool = false
    @Attribute(.externalStorage) var coverImage: Data?

    // Market value, filled in by online lookup (or by hand).
    var estimatedValue: Double?
    var valueLow: Double?
    var valueHigh: Double?
    var valueCurrency: String = ""
    var valueSource: String = ""
    var valueUpdated: Date?

    var dateAdded: Date = Date()
    var dateModified: Date = Date()

    init(title: String = "", format: MediaFormat = .dvd, barcode: String = "") {
        self.id = UUID()
        self.title = title
        self.formatRaw = format.rawValue
        self.barcode = barcode
        self.dateAdded = Date()
        self.dateModified = Date()
    }

    var format: MediaFormat {
        get { MediaFormat(rawValue: formatRaw) ?? .dvd }
        set { formatRaw = newValue.rawValue }
    }

    var videoStandard: VideoStandard {
        get { VideoStandard(rawValue: videoStandardRaw) ?? .unknown }
        set { videoStandardRaw = newValue.rawValue }
    }

    var condition: ItemCondition {
        get { ItemCondition(rawValue: conditionRaw) ?? .unknown }
        set { conditionRaw = newValue.rawValue }
    }

    var laserDiscType: LaserDiscType {
        get { LaserDiscType(rawValue: laserDiscTypeRaw) ?? .unknown }
        set { laserDiscTypeRaw = newValue.rawValue }
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : title
    }

    /// One-line summary used in lists, e.g. "Vinyl · Kate Bush · 1985".
    var subtitle: String {
        var parts: [String] = [format.rawValue]
        if format.kind == .music, !director.isEmpty { parts.append(director) }
        if format == .game, !platform.isEmpty { parts.append(platform) }
        if let year { parts.append(String(year)) }
        if format.showsVideoStandard, videoStandard != .unknown { parts.append(videoStandard.rawValue) }
        if !edition.isEmpty { parts.append(edition) }
        return parts.joined(separator: " · ")
    }

    var formattedValue: String? {
        guard let estimatedValue else { return nil }
        return estimatedValue.formatted(.currency(code: valueCurrency.isEmpty ? "USD" : valueCurrency))
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return [title, director, cast, genre, studio, edition, barcode,
                catalogNumber, location, notes, platform]
            .contains { $0.lowercased().contains(q) }
            || (year.map { String($0).contains(q) } ?? false)
    }
}
