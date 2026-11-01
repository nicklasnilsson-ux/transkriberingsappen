import Foundation

/// Storlek på videobilden i den hopfällda raden. Liten är standard; användaren kan
/// förstora till mellan och stor. 16:9.
public enum MiniPlayerSize: String, CaseIterable, Sendable {
    case small, medium, large

    public static let storageKey = "miniPlayerSize"
    public static let aspect: Double = 16.0 / 9.0

    /// Bredd i punkter. Liten är ungefär en fjärdedel av dagens spelarbredd (cirka 640 pt).
    public var width: Double {
        switch self {
        case .small: 128
        case .medium: 256
        case .large: 420
        }
    }

    public var height: Double { (width / Self.aspect).rounded() }

    public var label: String {
        switch self {
        case .small: "Liten"
        case .medium: "Mellan"
        case .large: "Stor"
        }
    }

    public static func resolved(_ raw: String?) -> MiniPlayerSize {
        raw.flatMap(MiniPlayerSize.init(rawValue:)) ?? .small
    }
}
