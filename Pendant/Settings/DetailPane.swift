import SwiftUI

/// The settings panel right of a tool list: it starts level with the list, runs down to the window's bottom, and its content
/// scrolls out under a soft fade at both ends instead of being cut off.
struct DetailPane<Content: View>: View {
    @Environment(\.pageViewportHeight) private var viewportHeight
    @State private var top: CGFloat = 200
    let minHeight: CGFloat
    @ViewBuilder let content: () -> Content

    private static var fade: CGFloat { 18 }

    var body: some View {
        let height = viewportHeight > 0 ? max(minHeight, viewportHeight - top - 24) : minHeight
        content()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                }
            )
            .background(GeometryReader { proxy in
                Color.clear.onChange(of: proxy.frame(in: .named(PageSpace.content)).minY, initial: true) { _, value in top = value }
            })
    }
}
