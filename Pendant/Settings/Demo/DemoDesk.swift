import SwiftUI

/// A small stand-in for the top of a Mac screen (wallpaper, menu bar, notch) that settings demos draw on. Content is laid out
/// on a virtual 1100 pt wide screen (real point sizes, so the island planner gives real results); only the middle `viewport` points
/// of it are shown, scaled to the width the page offers, so the objects fill most of the demo.
struct DemoDesk<Content: View>: View {
    static var screenWidth: CGFloat { 1100 }
    static var menuBarHeight: CGFloat { 32 }

    var viewport: CGFloat = 540
    var height: CGFloat = 150
    @ViewBuilder let content: () -> Content

    /// Left edge of the visible part, in screen coordinates.
    static func minX(viewport: CGFloat) -> CGFloat { (screenWidth - viewport) / 2 }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / viewport
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.17, green: 0.29, blue: 0.61), Color(red: 0.48, green: 0.25, blue: 0.54)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.black.opacity(0.3)).frame(height: Self.menuBarHeight)
                content().offset(x: -Self.minX(viewport: viewport))
            }
            .frame(width: viewport, height: height, alignment: .topLeading)
            .clipped()
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: proxy.size.width, height: height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .aspectRatio(viewport / height, contentMode: .fit)
    }
}

/// Reports scroll-wheel events over the view it covers, without taking clicks or hover from what is underneath.
struct DemoScrollCatcher: NSViewRepresentable {
    /// deltaX, deltaY, option key held
    let onScroll: (CGFloat, CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat, Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, event.modifierFlags.contains(.option))
        }
    }
}
