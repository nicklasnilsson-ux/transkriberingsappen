import SwiftUI

/// Lägger delvyerna på rad efter rad och bryter till en ny rad när nästa inte får plats.
/// Varje delvy får sin egen önskade bredd (aldrig hoptryckt), så att texten i till exempel
/// talarchipen alltid syns i sin helhet. En enda rad är högre bara om det behövs.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 6

    /// Radbrytningen som ren funktion av mått, så att den går att enhetstesta utan att rita.
    /// Returnerar radernas intervall i `widths` (index) för en given maxbredd.
    static func lines(widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        var x: CGFloat = 0
        for (i, w) in widths.enumerated() {
            let needed = i == start ? w : x + spacing + w
            if i > start, needed > maxWidth {
                result.append(start..<i)
                start = i
                x = w
            } else {
                x = needed
            }
        }
        if start < widths.count { result.append(start..<widths.count) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows.lines {
            var x = bounds.minX
            for i in row.range {
                let size = rows.sizes[i]
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Arrangement {
        var sizes: [CGSize]
        var lines: [(range: Range<Int>, height: CGFloat)]
        var width: CGFloat
        var height: CGFloat
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let ranges = Self.lines(widths: sizes.map(\.width), maxWidth: width, spacing: spacing)
        let lines = ranges.map { range in
            (range: range, height: sizes[range].map(\.height).max() ?? 0)
        }
        let widest = ranges.map { r in sizes[r].map(\.width).reduce(0, +) + spacing * CGFloat(r.count - 1) }.max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return Arrangement(sizes: sizes, lines: lines, width: widest, height: height)
    }
}
