import AppKit
import Carbon.HIToolbox

/// System-wide shortcut through Carbon's `RegisterEventHotKey` (needs no Accessibility permission).
@MainActor
final class GlobalHotkey {
    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// - Parameters:
    ///   - keyCode: virtual key code (e.g. 49 = Space).
    ///   - modifiers: `NSEvent.ModifierFlags` raw value (⌥ = 1 << 19 …).
    @discardableResult
    func register(keyCode: Int, modifiers: Int) -> Bool {
        unregister()
        guard keyCode >= 0, Self.carbonModifiers(from: modifiers) != 0 else { return false }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotkey.onTrigger?() } }
            return noErr
        }, 1, &eventType, userData, &handlerRef)
        guard status == noErr else { return false }

        let identifier = EventHotKeyID(signature: OSType(0x4E4F4F4B), id: 1) // 'NOOK'
        let registered = RegisterEventHotKey(
            UInt32(keyCode), Self.carbonModifiers(from: modifiers), identifier, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if registered != noErr { unregister() }
        return registered == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    /// Converts `NSEvent.ModifierFlags` raw values to Carbon masks.
    static func carbonModifiers(from raw: Int) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(raw))
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    /// "⌥Space", "⌃⌘K" …
    static func displayString(keyCode: Int, modifiers: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyName(for: keyCode)
    }

    private static let specialKeys: [Int: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
    ]
    private static let letterKeys: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]

    static func keyName(for keyCode: Int) -> String {
        specialKeys[keyCode] ?? letterKeys[keyCode] ?? "Key \(keyCode)"
    }
}
