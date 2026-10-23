import SwiftUI

/// Lays its children out left to right and wraps them onto new lines, each at its own size.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 300, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var offsetX: CGFloat = 0, offsetY: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if offsetX > 0, offsetX + size.width > width { offsetX = 0; offsetY += rowHeight + (lineSpacing ?? spacing); rowHeight = 0 }
            origins.append(CGPoint(x: offsetX, y: offsetY))
            offsetX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: offsetY + rowHeight), origins)
    }
}
