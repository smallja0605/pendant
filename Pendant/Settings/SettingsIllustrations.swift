import SwiftUI

/// The small pictures at the top of the settings pages: they explain what the page controls, drawn with the app's own look (no
/// bitmaps, so they stay sharp and follow the window's size).
enum SettingsIllustration {
    case islands, shelf, statusBar, appearance

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .islands: IslandsIllustration()
        case .shelf: ShelfIllustration()
        case .statusBar: StatusBarIllustration()
        case .appearance: AppearanceIllustration()
        }
    }
}

extension View {
    /// Puts a settings page's picture first (under the title): a plain row without the card background.
    func illustrationRow() -> some View {
        frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}

/// Frame shared by all pictures: a soft card with the picture centred (no caption: the page's own heading says what it is).
struct IllustrationFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.vertical, 18).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private let wallpaper = LinearGradient(
    colors: [Color(red: 0.18, green: 0.3, blue: 0.62), Color(red: 0.5, green: 0.28, blue: 0.58)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

/// The real notch / capsule silhouette: flat on top (it hangs from the screen's edge), rounded at the bottom.
private func hanging(_ radius: CGFloat) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
}

/// A loose hand-drawn stroke with a small loop in it (like pen marks on a sketch), drawn from its bottom end up to the thing it
/// points at. `mirrored` swings it the other way.
private struct Squiggle: Shape {
    var mirrored = false

    /// The user's own stroke, traced: it rises from the bottom-left to a junction, makes a small lens-shaped loop to the right of
    /// it (along the top, down the right side, back up the left) and runs on to the upper right. Coordinates are from the 4× enlarged
    /// sketch (x 80…380, y 100…632) and are fitted into `rect`, keeping the proportions.
    func path(in rect: CGRect) -> Path {
        let minX = 80.0, width = 300.0, minY = 100.0, height = 532.0
        let scale = min(rect.width / width, rect.height / height)
        let originX = rect.minX + (rect.width - width * scale) / 2
        func point(_ px: Double, _ py: Double) -> CGPoint {
            let fx = (px - minX) * scale
            return CGPoint(x: mirrored ? originX + width * scale - fx : originX + fx, y: rect.maxY - (height - (py - minY)) * scale)
        }
        var path = Path()
        path.move(to: point(80, 632))
        path.addCurve(to: point(205, 375), control1: point(110, 540), control2: point(150, 440))
        path.addCurve(to: point(260, 325), control1: point(225, 350), control2: point(245, 332)) // the junction
        path.addCurve(to: point(333, 320), control1: point(285, 314), control2: point(318, 312)) // along the top of the loop
        path.addCurve(to: point(300, 388), control1: point(340, 335), control2: point(325, 370)) // down its right side
        path.addCurve(to: point(258, 385), control1: point(285, 400), control2: point(262, 404)) // under it
        path.addCurve(to: point(260, 325), control1: point(255, 365), control2: point(256, 340)) // back up to the junction
        path.addCurve(to: point(380, 100), control1: point(272, 285), control2: point(310, 200)) // and away
        return path
    }
}

private struct HandNote: View {
    let text: String
    var mirrored = false

    var body: some View {
        Squiggle(mirrored: mirrored)
            .stroke(.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            .frame(width: 36, height: 62)
            // The traced stroke leans about 29° to the right; turned back so it stands almost upright.
            .rotationEffect(.degrees(mirrored ? 26 : -26))
            .overlay(alignment: .bottom) {
                // Handwritten (Hannotate TC), set under the stroke's lower end.
                Text(text).font(.custom("HannotateTC-W7", size: 22)).foregroundStyle(.white).fixedSize()
                    .offset(x: mirrored ? 4 : -4, y: 34)
            }
    }
}

// MARK: 動態島

/// Main island (cover and waveform) next to the notch and a secondary island (a timer), both hanging from the top edge.
struct IslandsIllustration: View {
    var body: some View {
        IllustrationFrame {
            ZStack(alignment: .top) {
                wallpaper
                // The menu bar is exactly as tall as the notch, so the islands fill its height.
                Rectangle().fill(.black.opacity(0.35)).frame(height: 32).frame(maxHeight: .infinity, alignment: .top)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        HStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                                .frame(width: 18, height: 18)
                            Spacer()
                            HStack(spacing: 2.5) {
                                ForEach([8.0, 13.0, 10.0], id: \.self) { Capsule().fill(.white).frame(width: 3, height: $0) }
                            }
                        }
                        .padding(.horizontal, 20).frame(width: 246, height: 32)
                        // The real notch outline: flat top with the concave ears where it meets the menu bar.
                        .background(NotchShape(bottomRadius: 14).fill(Color.black))
                        Text("01:28").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 28).background(Capsule().fill(Color.black))
                            .padding(.top, 2)
                    }
                    ZStack(alignment: .topLeading) {
                        HandNote(text: "主島").offset(x: 74, y: 14)
                        HandNote(text: "副島", mirrored: true).offset(x: 328, y: 14)
                    }
                    .frame(width: 440, height: 90, alignment: .topLeading)
                }
            }
            .frame(width: 440, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: 檔案中轉站

/// The shelf panel: an empty drop slot and a file that is already on it.
struct ShelfIllustration: View {
    var body: some View {
        IllustrationFrame {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [2, 5]))
                    .overlay(Image(systemName: "arrow.down.doc").font(.system(size: 22)).foregroundStyle(.white.opacity(0.6)))
                    .frame(width: 150, height: 78)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.45, green: 0.75, blue: 0.95))
                    .overlay(Image(systemName: "doc.fill").font(.system(size: 26)).foregroundStyle(.white))
                    .frame(width: 78, height: 78)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
            .background(hanging(24).fill(Color.black))
        }
    }
}

// MARK: 狀態列

/// Zoomed on the open capsule's top-right corner: the modules run off the frame to the left and below, and the battery and the
/// update tag sit in the corner.
struct StatusBarIllustration: View {
    var body: some View {
        IllustrationFrame {
            ZStack(alignment: .topTrailing) {
                wallpaper
                // The capsule is bigger than the frame: only its top-right corner is in view.
                ZStack(alignment: .topTrailing) {
                    UnevenRoundedRectangle(bottomTrailingRadius: 30, style: .continuous).fill(Color.black)
                        .frame(width: 520, height: 132)
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.25)).frame(width: 190, height: 80)
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.25)).frame(width: 190, height: 80)
                    }
                    .padding(.top, 38).padding(.trailing, 28)
                    HStack(spacing: 10) {
                        Text("有新版本可用").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 0.42, green: 0.05, blue: 0.1))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color(red: 1, green: 0.78, blue: 0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        HStack(spacing: 4) {
                            Text("100%").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                            Image(systemName: "battery.100percent").font(.system(size: 16)).foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 10).padding(.trailing, 16)
                }
                .padding(.trailing, 22).padding(.top, 0)
                .frame(width: 440, height: 150, alignment: .topTrailing)
                .clipped()
            }
            .frame(width: 440, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: 外觀

/// The same controls twice — a button, a segmented group, a slider — as ordinary views and as Liquid Glass.
struct AppearanceIllustration: View {
    var body: some View {
        IllustrationFrame {
            HStack(spacing: 0) {
                column(glass: false)
                Rectangle().fill(.white.opacity(0.3)).frame(width: 3, height: 150).clipShape(Capsule())
                column(glass: true)
            }
            .frame(width: 520)
        }
    }

    private func column(glass: Bool) -> some View {
        ZStack {
            // The same colourful backdrop under both, so the difference is the control itself.
            LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing)
                .frame(width: 180, height: 110).blur(radius: 22).opacity(0.85)
            ControlsSample(glass: glass)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ControlsSample: View {
    let glass: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).modifier(PlainOrGlass(glass: glass, radius: 21))
                HStack(spacing: 0) {
                    Image(systemName: "list.bullet").frame(width: 46, height: 30)
                        .modifier(PlainOrGlass(glass: glass, radius: 15))
                    Image(systemName: "square.grid.2x2").frame(width: 46, height: 30).foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(3).background(Capsule().fill(.black.opacity(glass ? 0.12 : 0.3)))
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.28)).frame(width: 150, height: 6)
                Capsule().fill(.white).frame(width: 90, height: 6)
                Color.clear.frame(width: 34, height: 22).modifier(PlainOrGlass(glass: glass, radius: 11)).offset(x: 76)
            }
            .frame(width: 150, height: 24, alignment: .leading)
        }
    }
}

private struct PlainOrGlass: ViewModifier {
    let glass: Bool
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if glass, #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(Color(white: 0.3), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

#if DEBUG
import AppKit

/// PENDANT_DEBUG_ILLUSTRATIONS=<folder>: renders each picture to a PNG there (for review before they go into the pages).
@MainActor
enum IllustrationExporter {
    static func export(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let all: [(String, AnyView)] = [
            ("islands", AnyView(IslandsIllustration())), ("shelf", AnyView(ShelfIllustration())),
            ("statusbar", AnyView(StatusBarIllustration())), ("appearance", AnyView(AppearanceIllustration())),
        ]
        for (name, view) in all {
            let framed = view.padding(16).frame(width: 560).background(Color(white: 0.16)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: framed)
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
#endif
