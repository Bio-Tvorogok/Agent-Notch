import SwiftUI

struct RowActivityLine: LayoutValueKey { static let defaultValue = false }

/// Wrap small metadata fields instead of squeezing titles and branch names out of a narrow list.
struct RowPartsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: positions(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = positions(subviews, width: bounds.width)
        for (i, view) in subviews.enumerated() {
            let frame = plan.frames[i]
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    private func positions(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var lineStart = 0
        let gap: CGFloat = 6
        // Small marks and bars sit on the middle of their line, not at its top.
        func centerLine() {
            for i in lineStart..<frames.count where frames[i] != .zero {
                frames[i].origin.y += (rowHeight - frames[i].height) / 2
            }
            lineStart = frames.count
        }
        for view in subviews {
            let line = view[RowActivityLine.self]
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: line ? width : min(width, ideal.width), height: nil))
            if size.width == 0 && size.height == 0 { frames.append(.zero); continue }
            if x > 0 && (line || x + size.width > width) {
                centerLine()
                x = 0; y += rowHeight + 2; rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: min(width, size.width), height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + gap
            if line { centerLine(); x = 0; y += rowHeight + 2; rowHeight = 0 }
        }
        centerLine()
        return (frames, max(0, y + rowHeight))
    }
}
