import Foundation

/// Uppspelningshastighet i spelarraden (Nicklas 2026-11-07): 0,75× till 2×, 1× är normal.
/// Hastigheten sparas och gäller alla filer. Tonhöjden behålls alltid (se `PlayerController`).
public enum PlaybackSpeed {
    public static let steps: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    public static let normal: Double = 1

    /// Närmaste giltiga steg (t.ex. om ett gammalt eller trasigt värde är sparat).
    public static func clamped(_ speed: Double) -> Double {
        guard speed.isFinite else { return normal }
        return steps.min { abs($0 - speed) < abs($1 - speed) } ?? normal
    }

    /// Nästa snabbare steg, eller samma om den redan är snabbast.
    public static func faster(than speed: Double) -> Double {
        let current = clamped(speed)
        return steps.first { $0 > current } ?? current
    }

    /// Nästa långsammare steg, eller samma om den redan är långsammast.
    public static func slower(than speed: Double) -> Double {
        let current = clamped(speed)
        return steps.last { $0 < current } ?? current
    }

    public static func isNormal(_ speed: Double) -> Bool { clamped(speed) == normal }

    /// Kort etikett med decimalkomma, t.ex. "1,25×" eller "2×". Står på knappen i spelarraden.
    public static func label(_ speed: Double) -> String {
        let value = clamped(speed)
        let number = value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
        return number.replacingOccurrences(of: ".", with: ",") + "×"
    }

    /// Etiketten i menyerna: som `label`, men 1× heter "1× (Normal)" (Nicklas 2026-11-07).
    public static func menuLabel(_ speed: Double) -> String {
        isNormal(speed) ? "\(label(speed)) (Normal)" : label(speed)
    }
}
