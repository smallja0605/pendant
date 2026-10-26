import SwiftUI

/// Reports whether the page's scroll view (the first one in the right-hand pane) has scrolled the big title out of sight. The
/// pages are SwiftUI forms / scroll views, so their `NSScrollView` is found in the window and its clip view's bounds are watched.
struct ScrollPastTitleObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = onChange
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) { probe.onChange = onChange }

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol? // removed with the view: the notification block holds both weakly
        private var past = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // The page is built a moment after this view appears.
            for delay in [0.05, 0.3, 0.9] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.attach() }
            }
        }

        private func attach() {
            #if DEBUG
            if ProcessInfo.processInfo.environment["PENDANT_DEBUG_SCROLLDUMP"] != nil, let root = window?.contentView {
                func dump(_ view: NSView, _ depth: Int) {
                    if view is NSScrollView || depth < 3 {
                        fputs("\(String(repeating: " ", count: depth))\(type(of: view)) \(view.convert(view.bounds, to: nil))\n", stderr)
                    }
                    view.subviews.forEach { dump($0, depth + 1) }
                }
                dump(root, 0)
            }
            #endif
            guard observer == nil, let root = window?.contentView, let scroll = Self.firstScrollView(in: root) else { return }
            scroll.contentView.postsBoundsChangedNotifications = true
            #if DEBUG
            // PENDANT_DEBUG_SETTINGS_SCROLL=<points>: scrolls the page by that much (for screenshots of the pinned title).
            if let raw = ProcessInfo.processInfo.environment["PENDANT_DEBUG_SETTINGS_SCROLL"], let points = Double(raw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak scroll] in
                    guard let scroll else { return }
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: points))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            #endif
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self, weak scroll] _ in
                guard let self, let scroll else { return }
                let offset = scroll.contentView.bounds.origin.y + scroll.contentInsets.top
                let nowPast = offset > 46
                if nowPast != past {
                    past = nowPast
                    onChange?(nowPast)
                }
            }
        }

        /// Outermost scroll view that sits right of the sidebar.
        private static func firstScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.convert(scroll.bounds, to: nil).minX > 150, scroll.documentView != nil {
                return scroll
            }
            for sub in view.subviews {
                if let found = firstScrollView(in: sub) { return found }
            }
            return nil
        }
    }
}

/// The page title pinned at the top once the big one has scrolled away: a frosted band that fades out downwards, so content
/// passing under it dissolves instead of being cut off.
struct TitleBand: View {
    let title: String
    let visible: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBackground(material: .menu, blending: .withinWindow)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
            Text(loc(title)).font(.system(size: 17, weight: .semibold)).padding(.leading, 28).padding(.top, 15)
        }
        .frame(height: 64)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -12)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: visible)
        .allowsHitTesting(false)
    }
}

/// The soft edge where a page's content scrolls out under the window's top or bottom: a blur that fades in towards the edge.
struct EdgeBlur: View {
    let edge: VerticalEdge
    let height: CGFloat

    var body: some View {
        VisualEffectBackground(material: .menu, blending: .withinWindow)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: edge == .top ? .top : .bottom,
                                 endPoint: edge == .top ? .bottom : .top))
            .frame(height: height)
            .allowsHitTesting(false)
    }
}
