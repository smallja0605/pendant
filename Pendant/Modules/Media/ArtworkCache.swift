import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Remembers the cover of every track that was shown, so coming back to it (or skipping through a playlist again) swaps the
/// cover at once. Lives in `~/Library/Caches/com.smallja.pendant/Artwork`, files are small JPEGs named by a hash of the
/// track (no titles on disk), the oldest are dropped past a size limit, and the media settings can switch it off or clear it.
actor ArtworkCache {
    static let shared = ArtworkCache()
    static let maxBytes = 40_000_000
    static let maxEntries = 400

    private let memory = NSCache<NSString, NSData>()
    private let folder: URL

    init(folder: URL? = nil) {
        memory.countLimit = 24
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.smallja.pendant", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
    }

    /// File name for a track: a hash, never the title.
    nonisolated static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(40) + ".jpg"
    }

    func load(_ key: String) -> Data? {
        let name = Self.fileName(for: key)
        if let cached = memory.object(forKey: name as NSString) { return cached as Data }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        memory.setObject(data as NSData, forKey: name as NSString)
        return data
    }

    /// Stores a downsized JPEG of `imageData`.
    func store(_ imageData: Data, for key: String) {
        guard let jpeg = Self.jpeg(from: imageData) else { return }
        let name = Self.fileName(for: key)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)
        memory.setObject(jpeg as NSData, forKey: name as NSString)
        trim()
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
    }

    func sizeInBytes() -> Int {
        files().reduce(0) { $0 + $1.size }
    }

    // MARK: Helpers

    private struct CachedFile {
        let url: URL
        let size: Int
        let date: Date
    }

    private func files() -> [CachedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return CachedFile(url: url, size: values?.fileSize ?? 0, date: values?.contentModificationDate ?? .distantPast)
        }
    }

    /// Drops the oldest files until the folder is within its limits.
    private func trim() {
        var all = files().sorted { $0.date < $1.date }
        var total = all.reduce(0) { $0 + $1.size }
        while !all.isEmpty, total > Self.maxBytes || all.count > Self.maxEntries {
            let oldest = all.removeFirst()
            total -= oldest.size
            try? FileManager.default.removeItem(at: oldest.url)
        }
    }

    nonisolated static func jpeg(from data: Data, maxPixelSize: Int = ArtworkDecoder.maxPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
