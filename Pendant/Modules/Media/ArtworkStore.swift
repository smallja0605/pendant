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

    init(image: NSImage) {
        self.image = image
        color = ArtworkDecoder.averageColor(of: image).map { Color(nsColor: ArtworkDecoder.vivid($0)) }
    }

    init?(_ data: Data) {
        guard let image = ArtworkDecoder.thumbnail(from: data) else { return nil }
        self.init(image: image)
    }
}
