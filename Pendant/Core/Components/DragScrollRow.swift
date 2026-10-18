import SwiftUI

/// A single row of content that never wraps and scrolls sideways: by dragging it with the mouse, or with a two-finger
/// swipe. The ends fade out (only on a side that has more content hidden behind it).
struct DragScrollRow<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    @State private var contentWidth: CGFloat = 0
    @State private var viewWidth: CGFloat = 0

    private var minOffset: CGFloat { min(viewWidth - contentWidth, 0) }
    private var scrollable: Bool { minOffset < 0 }

    var body: some View {
        content
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { contentWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in contentWidth = width; clampOffset() }
            })
            .offset(x: offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { viewWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in viewWidth = width; clampOffset() }
            })
            .clipped()
            .mask(fade)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { drag in
                        guard scrollable else { return }
                        let start = dragStart ?? offset
                        dragStart = start
                        offset = Self.rubberBand(start + drag.translation.width, in: minOffset...0)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { clampOffset() }
                    }
            )
            .onScrollWheelConsuming { deltaX, deltaY in
                guard scrollable, abs(deltaX) > abs(deltaY) else { return false }
                offset = min(max(offset + deltaX, minOffset), 0)
                return true
            }
    }

    private var fade: some View {
        let left = offset < -1
        let right = offset > minOffset + 1
        return LinearGradient(
            stops: [.init(color: left ? .clear : .black, location: 0), .init(color: .black, location: left ? 0.1 : 0),
                    .init(color: .black, location: right ? 0.9 : 1), .init(color: right ? .clear : .black, location: 1)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private func clampOffset() { offset = min(max(offset, minOffset), 0) }

    /// Past either end the row follows the pointer with growing resistance, then springs back on release.
    static func rubberBand(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        if value > range.upperBound { return range.upperBound + (value - range.upperBound) * 0.3 }
        if value < range.lowerBound { return range.lowerBound + (value - range.lowerBound) * 0.3 }
        return value
    }
}
