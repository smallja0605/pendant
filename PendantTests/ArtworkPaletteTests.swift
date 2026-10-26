import AppKit
import Testing
@testable import Pendant

struct ArtworkPaletteTests {
    /// A 40 × 40 picture: the left half one colour, the right half another.
    private func image(left: NSColor, right: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.lockFocus()
        left.setFill(); NSRect(x: 0, y: 0, width: 20, height: 40).fill()
        right.setFill(); NSRect(x: 20, y: 0, width: 20, height: 40).fill()
        image.unlockFocus()
        return image
    }

    private func hue(_ color: NSColor) -> Double {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        (color.usingColorSpace(.deviceRGB) ?? color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(hue)
    }

    @Test func twoColourfulHalvesGiveTwoDifferentHues() {
        let palette = ArtworkDecoder.palette(of: image(left: NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1),
                                                      right: NSColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)))
        #expect(palette.count == 2)
        let hues = palette.map(hue).sorted()
        #expect(hues[0] < 0.1 || hues[0] > 0.9) // a red
        #expect(abs(hues[1] - 0.64) < 0.08 || abs(hues[0] - 0.64) < 0.08) // a blue
    }

    @Test func aGreyCoverGivesASoftWhitePair() {
        let palette = ArtworkDecoder.palette(of: image(left: .gray, right: .darkGray))
        #expect(palette.count == 2)
        #expect(palette.allSatisfy { ($0.usingColorSpace(.deviceRGB)?.saturationComponent ?? 1) < 0.05 })
    }

    @Test func theFadeMovesFromOnePairToAnother() {
        let fade = ColorFade()
        let red = [NSColor.red, NSColor.red]
        fade.move(to: red)
        let start = Date()
        #expect(fade.colors(at: start.addingTimeInterval(5)).first?.usingColorSpace(.deviceRGB)?.redComponent ?? 0 > 0.99)
        fade.move(to: [NSColor.blue, NSColor.blue])
        let middle = fade.colors(at: Date().addingTimeInterval(0.4)).first?.usingColorSpace(.deviceRGB)
        #expect((middle?.redComponent ?? 0) > 0.2 && (middle?.redComponent ?? 0) < 0.8) // half way
        let done = fade.colors(at: Date().addingTimeInterval(2)).first?.usingColorSpace(.deviceRGB)
        #expect((done?.blueComponent ?? 0) > 0.99)
    }
}
