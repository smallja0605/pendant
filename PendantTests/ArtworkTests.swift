import AppKit
import Foundation
import Testing
@testable import Pendant

struct CatalogArtworkTests {
    @Test func searchURLSendsOnlyTitleAndArtistToApple() {
        let url = CatalogArtworkFetcher.searchURL(title: "Cookie", artist: "NewJeans")
        #expect(url?.host == "itunes.apple.com")
        #expect(url?.scheme == "https")
        #expect(url?.query?.contains("term=Cookie") == true)
    }

    @Test func imageHostsAreAllowListed() {
        #expect(CatalogArtworkFetcher.isAllowedImage(URL(string: "https://is1-ssl.mzstatic.com/image/x/600x600bb.jpg")!))
        #expect(!CatalogArtworkFetcher.isAllowedImage(URL(string: "https://evil.example.com/a.jpg")!))
        #expect(!CatalogArtworkFetcher.isAllowedImage(URL(string: "http://is1-ssl.mzstatic.com/a.jpg")!))
    }

    @Test func picksTheHitFromTheSameAlbumAndAsksForALargerImage() {
        let json = """
        {"results":[
          {"artworkUrl100":"https://is1-ssl.mzstatic.com/a/100x100bb.jpg","collectionName":"Other"},
          {"artworkUrl100":"https://is1-ssl.mzstatic.com/b/100x100bb.jpg","collectionName":"NewJeans 1st EP 'New Jeans'"}]}
        """
        let url = CatalogArtworkFetcher.artworkURL(in: Data(json.utf8), album: "NewJeans 1st EP")
        #expect(url?.absoluteString == "https://is1-ssl.mzstatic.com/b/600x600bb.jpg")
    }
}

struct ArtworkCacheTests {
    private func sampleJPEG() -> Data {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemPink.setFill()
            rect.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func fileNamesAreHashesNotTitles() {
        let name = ArtworkCache.fileName(for: "Cookie|NewJeans|Single")
        #expect(!name.contains("Cookie"))
        #expect(name.hasSuffix(".jpg"))
        #expect(name == ArtworkCache.fileName(for: "Cookie|NewJeans|Single"))
        #expect(name != ArtworkCache.fileName(for: "Hurt|NewJeans|Single"))
    }

    @Test func storesLoadsAndClears() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ArtworkCache(folder: folder)
        #expect(await cache.load("a") == nil)
        await cache.store(sampleJPEG(), for: "a")
        #expect(await cache.load("a") != nil)
        #expect(await cache.sizeInBytes() > 0)
        await cache.clear()
        #expect(await cache.load("a") == nil)
        #expect(await cache.sizeInBytes() == 0)
    }
}
