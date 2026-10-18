#if DEBUG
import AppKit
import SwiftUI

/// Draws the app icon (a notch hanging from the top of a dark rounded square, a desk lamp below it) so the asset catalog's PNGs
/// can be regenerated: PENDANT_DEBUG_ICON=<folder> writes every size there (copy them into AppIcon.appiconset).
struct AppIconArt: View {
    /// Full 1024 pt canvas; the icon square is 824 pt inset by 100 (Apple's grid).
    var body: some View {
        let side: CGFloat = 824
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.5), Color(red: 0.04, green: 0.04, blue: 0.14)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: side, height: side)
            VStack(spacing: 0) {
                // The notch: short, flat on top, rounded below.
                UnevenRoundedRectangle(bottomLeadingRadius: 70, bottomTrailingRadius: 70, style: .continuous)
                    .fill(Color.black).frame(width: side * 0.6, height: side * 0.2)
                Spacer(minLength: 0)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
            Image(systemName: "lamp.desk.fill")
                .font(.system(size: side * 0.5, weight: .regular))
                .foregroundStyle(.white)
                .offset(y: side * 0.13)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
enum AppIconExporter {
    static func export(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16@1x", 16), ("icon_16x16@2x", 32), ("icon_32x32@1x", 32), ("icon_32x32@2x", 64),
            ("icon_128x128@1x", 128), ("icon_128x128@2x", 256), ("icon_256x256@1x", 256), ("icon_256x256@2x", 512),
            ("icon_512x512@1x", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            let renderer = ImageRenderer(content: AppIconArt())
            renderer.scale = pixels / 1024
            guard let image = renderer.cgImage else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
#endif
