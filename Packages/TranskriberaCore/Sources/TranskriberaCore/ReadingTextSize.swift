import Foundation

/// Textstorlek på läsytan (transkriberingens text). Fyra steg; 15 pt är standard.
public enum ReadingTextSize {
    /// Standard 16 pt, den största av appens tre textstorlekar (Nicklas 2026-11-06). Stegen över
    /// är ett personligt val för den som vill läsa större (⌘+), inte en del av gränssnittets skala.
    public static let steps: [Double] = [14, 16, 18, 20]
    public static let standard: Double = 16

    /// Närmaste giltiga steg (t.ex. om ett gammalt eller trasigt värde är sparat). Mitt emellan två
    /// steg blir det större, så att de gamla stegen 13/15/17 blir 14/16/18 och ingen får mindre text.
    public static func clamped(_ size: Double) -> Double {
        steps.min { (abs($0 - size), -$0) < (abs($1 - size), -$1) } ?? standard
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

    /// Högsta bredd på textspalten, cirka 72 tecken per rad. Gäller både stycken och rader, så att
    /// texten är lika bred i båda visningarna och i redigeringsläget (Nicklas 2026-11-04).
    public static func columnWidth(for size: Double) -> Double {
        clamped(size) * 40
    }
}
