import AppKit
import ImageIO
import SwiftUI

/// Decodes artwork to a bounded thumbnail and keeps a few of them (memory budget, requirements 2.1).
enum ArtworkDecoder {
    static let maxPixelSize = 480

    static func thumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Lifts dull / dark averages so the cover's shadow and glow stay visible on a black capsule.
    static func vivid(_ color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(1, saturation * 1.25 + 0.05), brightness: max(brightness, 0.62), alpha: 1)
    }

    /// Two colours of the cover for a gradient (the lighter one first): the two most colourful hues, each lifted to be seen on black.
    /// A cover with no real colour gives a soft white-to-grey pair.
    static func palette(of image: NSImage) -> [NSColor] {
        let side = 24
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return fallbackPalette }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return fallbackPalette }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Twelve hue buckets, each weighing its pixels by how colourful and how bright they are.
        var weight = [Double](repeating: 0, count: 12)
        var sums = [[Double]](repeating: [0, 0, 0], count: 12)
        for index in 0..<side * side {
            let color = NSColor(red: Double(pixels[index * 4]) / 255, green: Double(pixels[index * 4 + 1]) / 255,
                                blue: Double(pixels[index * 4 + 2]) / 255, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            guard saturation > 0.2, brightness > 0.2 else { continue }
            let bucket = min(Int(hue * 12), 11)
            let share = Double(saturation * brightness)
            weight[bucket] += share
            sums[bucket][0] += Double(hue) * share
            sums[bucket][1] += Double(saturation) * share
            sums[bucket][2] += Double(brightness) * share
        }
        let ranked = weight.indices.filter { weight[$0] > 0 }.sorted { weight[$0] > weight[$1] }
        guard let first = ranked.first, weight[first] > 1.5 else { return fallbackPalette }
        func color(_ bucket: Int) -> NSColor {
            let total = weight[bucket]
            return lifted(hue: sums[bucket][0] / total, saturation: sums[bucket][1] / total, brightness: sums[bucket][2] / total)
        }
        let main = color(first)
        // The second hue: the next bucket that is not a neighbour of the first, else the same hue turned a little.
        let other = ranked.dropFirst().first { bucket in
            let distance = abs(bucket - first)
            return min(distance, 12 - distance) >= 2 && weight[bucket] > weight[first] * 0.15
        }
        let second = other.map(color) ?? lifted(hue: (sums[first][0] / weight[first] + 0.07).truncatingRemainder(dividingBy: 1),
                                                saturation: sums[first][1] / weight[first] * 0.8, brightness: 1)
        return brightnessOf(main) > brightnessOf(second) ? [main, second] : [second, main]
    }

    private static var fallbackPalette: [NSColor] { [NSColor(white: 0.95, alpha: 1), NSColor(white: 0.62, alpha: 1)] }

    private static func lifted(hue: Double, saturation: Double, brightness: Double) -> NSColor {
        NSColor(hue: hue, saturation: min(1, max(saturation, 0.45)), brightness: max(brightness, 0.82), alpha: 1)
    }

    private static func brightnessOf(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }

    /// Average colour, for the faint glow behind the media page.
    static func averageColor(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255, alpha: 1)
    }
}

/// The only network access besides update checks: Spotify cover art over HTTPS from Spotify's image
/// CDN, no cookies, no user data (documented exception to requirement 13.2 — see DECISIONS.md).
actor SpotifyArtworkFetcher {
    static let shared = SpotifyArtworkFetcher()
    static let allowedHosts: Set<String> = ["i.scdn.co"]
    static let maxBytes = 3_000_000

    private let cache = NSCache<NSString, NSData>()
    private let session: URLSession

    init() {
        cache.countLimit = 8
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    /// Only https URLs on the allow-listed Spotify image host are fetched.
    nonisolated static func isAllowed(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host) else { return nil }
        return url
    }

    func fetch(_ urlString: String) async -> Data? {
        guard let url = Self.isAllowed(urlString) else { return nil }
        if let cached = cache.object(forKey: urlString as NSString) { return cached as Data }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= Self.maxBytes else { return nil }
        cache.setObject(data as NSData, forKey: urlString as NSString)
        return data
    }
}

private struct CatalogSearchItem: Decodable {
    let artworkUrl100: String?
    let collectionName: String?
}

private struct CatalogSearchResponse: Decodable {
    let results: [CatalogSearchItem]
}

/// Cover art for streamed Apple Music tracks from Apple's public iTunes Search API. Sends only title / artist (and album
/// to pick the right hit), https only, allow-listed hosts, no cookies, nothing stored on disk (documented exception, see
/// DECISIONS.md; switchable off in the media settings).
actor CatalogArtworkFetcher {
    static let shared = CatalogArtworkFetcher()
    static let searchHost = "itunes.apple.com"
    static let imageHostSuffix = ".mzstatic.com"
    static let maxBytes = 3_000_000

    private let cache = NSCache<NSString, NSData>()
    private let session: URLSession

    init() {
        cache.countLimit = 8
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    nonisolated static func searchURL(title: String, artist: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = searchHost
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        return components.url
    }

    nonisolated static func isAllowedImage(_ url: URL) -> Bool {
        url.scheme == "https" && (url.host?.lowercased().hasSuffix(imageHostSuffix) ?? false)
    }

    /// Picks the best hit (same album if possible) and the larger cover image URL.
    nonisolated static func artworkURL(in data: Data, album: String) -> URL? {
        guard let response = try? JSONDecoder().decode(CatalogSearchResponse.self, from: data) else { return nil }
        let items = response.results.filter { $0.artworkUrl100 != nil }
        let hit = items.first { !album.isEmpty && $0.collectionName?.localizedCaseInsensitiveContains(album) == true } ?? items.first
        guard let small = hit?.artworkUrl100 else { return nil }
        let large = small.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: large).flatMap { isAllowedImage($0) ? $0 : nil }
    }

    func fetch(title: String, artist: String, album: String) async -> Data? {
        guard !title.isEmpty else { return nil }
        let key = "\(title)|\(artist)|\(album)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
        guard let url = Self.searchURL(title: title, artist: artist),
              let (list, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let imageURL = Self.artworkURL(in: list, album: album),
              let (image, imageResponse) = try? await session.data(from: imageURL),
              (imageResponse as? HTTPURLResponse)?.statusCode == 200,
              image.count <= Self.maxBytes else { return nil }
        cache.setObject(image as NSData, forKey: key)
        return image
    }
}

/// A decoded cover and its glow colour, produced off the main thread.
struct DecodedArtwork: @unchecked Sendable {
    let image: NSImage
    let color: Color?
    /// Two colours of the cover (lighter first) for the waveform's gradient.
    let palette: [Color]

    init(image: NSImage) {
        self.image = image
        color = ArtworkDecoder.averageColor(of: image).map { Color(nsColor: ArtworkDecoder.vivid($0)) }
        palette = ArtworkDecoder.palette(of: image).map { Color(nsColor: $0) }
    }

    init?(_ data: Data) {
        guard let image = ArtworkDecoder.thumbnail(from: data) else { return nil }
        self.init(image: image)
    }
}
