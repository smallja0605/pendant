import Foundation
import Testing
@testable import Pendant

struct SettingsTransferTests {
    private func suite() -> UserDefaults {
        let name = "pendant.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theKeyListsMatchTheSettingsSource() throws {
        // Every `save(…, "key")` of the two settings classes must be a known key (or the lists drift apart).
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func keys(_ file: String) throws -> Set<String> {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            let regex = try NSRegularExpression(pattern: #"save\([^,]+, "([A-Za-z0-9]+)"\)"#)
            return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range(at: 1), in: text).map { String(text[$0]) }
            })
        }
        #expect(try keys("Pendant/Core/AppSettings.swift") == Set(SettingsTransfer.appKeys))
        #expect(try keys("Pendant/Core/FocusCapsuleSettings.swift") == Set(SettingsTransfer.focusKeys))
    }

    @Test func exportThenImportCarriesTheSettings() throws {
        let source = suite()
        source.set(true, forKey: "settings.virtualFloating")
        source.set(0.3, forKey: "settings.lyricsOffset")
        source.set(5, forKey: "settings.focus.waveformBars")
        source.set("lyrics", forKey: "settings.virtualMiddle")
        source.set(["a", "b"], forKey: "settings.timerPresets")
        source.set(Data(#"[{"id":"x","kind":"custom","name":"N","enabled":true}]"#.utf8), forKey: "settings.lyricsSources")
        let file = try SettingsTransfer.export(from: source, appVersion: "1.2.3")
        let target = suite()
        let result = try SettingsTransfer.apply(file, to: target)
        #expect(result.applied == 6 && result.platform == "macOS")
        #expect(target.bool(forKey: "settings.virtualFloating"))
        #expect(target.double(forKey: "settings.lyricsOffset") == 0.3)
        #expect(target.integer(forKey: "settings.focus.waveformBars") == 5)
        #expect(target.string(forKey: "settings.virtualMiddle") == "lyrics")
        #expect(target.stringArray(forKey: "settings.timerPresets") == ["a", "b"])
        let blob = try #require(target.data(forKey: "settings.lyricsSources"))
        #expect(String(bytes: blob, encoding: .utf8)?.contains("\"custom\"") == true)
    }

    @Test func machineSpecificAndSecretThingsDoNotTravel() throws {
        let source = suite()
        source.set("/Users/someone/Notes", forKey: "settings.notesCustomPath")
        source.set("camera-id", forKey: "settings.mirrorCameraID")
        source.set(true, forKey: "settings.tourSeen")
        source.set("unrelated", forKey: "SomeOtherKey")
        source.set(true, forKey: "settings.hoverEffectEnabled")
        let text = String(decoding: try SettingsTransfer.export(from: source, appVersion: "1"), as: UTF8.self)
        #expect(!text.contains("notesCustomPath") && !text.contains("mirrorCameraID") && !text.contains("tourSeen") && !text.contains("SomeOtherKey"))
        #expect(text.contains("hoverEffectEnabled"))
    }

    @Test func aFileFromAnotherPlatformAppliesWhatFits() throws {
        let json = #"""
        {"format":"pendant-settings","version":1,"platform":"windows","common":{"lyricsOffset":-0.5,"hoverDelay":0.4,"somethingNew":7,
         "notesCustomPath":"C:\\x"},"windows":{"trayIcon":true},"macOS":{"liquidGlassEnabled":false}}
        """#
        let target = suite()
        let result = try SettingsTransfer.apply(Data(json.utf8), to: target)
        #expect(result.applied == 3) // lyricsOffset, hoverDelay and the Mac-only key from the "macOS" section
        #expect(result.ignored == 2) // somethingNew, notesCustomPath
        #expect(target.double(forKey: "settings.lyricsOffset") == -0.5)
        #expect(target.object(forKey: "settings.notesCustomPath") == nil)
    }

    @Test func aMacOnlyKeyInTheCommonSectionIsIgnored() throws {
        let json = #"{"format":"pendant-settings","version":1,"platform":"windows","common":{"liquidGlassEnabled":true}}"#
        let target = suite()
        #expect(try SettingsTransfer.apply(Data(json.utf8), to: target).applied == 0)
    }

    @Test func wrongFilesAreRefused() {
        #expect(throws: SettingsTransfer.TransferError.notASettingsFile) {
            try SettingsTransfer.apply(Data(#"{"format":"other"}"#.utf8), to: suite())
        }
        #expect(throws: SettingsTransfer.TransferError.newerVersion(9)) {
            try SettingsTransfer.apply(Data(#"{"format":"pendant-settings","version":9}"#.utf8), to: suite())
        }
        #expect(throws: SettingsTransfer.TransferError.unreadable) {
            try SettingsTransfer.apply(Data("not json".utf8), to: suite())
        }
    }

    @Test func aSettingMustBeAPlainValue() throws {
        let json = #"{"format":"pendant-settings","version":1,"common":{"hoverEffectEnabled":{"a":1},"hoverDelay":[1,2]}}"#
        let target = suite()
        let result = try SettingsTransfer.apply(Data(json.utf8), to: target)
        #expect(result.applied == 0 && result.ignored == 2)
    }
}
