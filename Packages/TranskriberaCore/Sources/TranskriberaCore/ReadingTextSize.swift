import Foundation

/// Textstorlek på läsytan (transkriberingens text). Fyra steg; 15 pt är standard.
public enum ReadingTextSize {
    public static let steps: [Double] = [13, 15, 17, 20]
    public static let standard: Double = 15

    /// Närmaste giltiga steg (t.ex. om ett gammalt eller trasigt värde är sparat).
    public static func clamped(_ size: Double) -> Double {
        steps.min { abs($0 - size) < abs($1 - size) } ?? standard
    }

    /// Nästa större steg, eller samma om den redan är störst.
    public static func larger(than size: Double) -> Double {
        let current = clamped(size)
        return steps.first { $0 > current } ?? current
    }

    /// Nästa mindre steg, eller samma om den redan är minst.
    public static func smaller(than size: Double) -> Double {
        let current = clamped(size)
        return steps.last { $0 < current } ?? current
    }
}
