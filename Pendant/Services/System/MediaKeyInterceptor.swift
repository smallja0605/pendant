import AppKit
import ApplicationServices

/// The volume / brightness / mute keys, taken before the system sees them (an event tap, which needs the Accessibility permission).
/// The system therefore neither changes the level nor shows its own pop-up; `SystemLevelMonitor` makes the change instead and the
/// notch HUD reports it. Without the permission nothing is tapped and the keys behave as usual.
@MainActor
final class MediaKeyInterceptor {
    enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }

    /// Called for every press (and key repeat) of an intercepted key; `fine` = shift + option held (quarter steps).
    /// Returns false when the key could not be handled (then it goes on to the system untouched, so it never goes dead).
    var onKey: ((Key, _ fine: Bool) -> Bool)?
    var interceptsVolume = true
    var interceptsBrightness = true

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its Accessibility prompt (once per call) when the permission is missing.
    static func requestPermission() {
        guard !AXIsProcessTrusted() else { return }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil, Self.isTrusted else { return tap != nil }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED: media keys arrive as system-defined events
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: mediaKeyTapCallback, userInfo: refcon
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the event was ours (to be swallowed).
    fileprivate func handle(keyCode: Int, isDown: Bool, fine: Bool) -> Bool {
        let key: Key
        switch keyCode {
        case 0 where interceptsVolume: key = .volumeUp
        case 1 where interceptsVolume: key = .volumeDown
        case 7 where interceptsVolume: key = .mute
        case 2 where interceptsBrightness: key = .brightnessUp
        case 3 where interceptsBrightness: key = .brightnessDown
        default: return false
        }
        // Only the press is handled; the release of a key whose press we took is swallowed with it.
        if isDown {
            let taken = onKey?(key, fine) ?? false
            swallowedPress = taken ? key : nil
            return taken
        }
        return swallowedPress == key
    }

    /// The key whose press was taken last (its release must be taken too, a pass-through press needs a pass-through release).
    fileprivate var swallowedPress: Key?
}

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { interceptor.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let data = ns.data1
    let keyCode = (data & 0xFFFF_0000) >> 16
    let flags = data & 0x0000_FFFF
    let isDown = ((flags & 0xFF00) >> 8) == 0xA
    let fine = event.flags.contains([.maskShift, .maskAlternate])
    let swallowed = MainActor.assumeIsolated { interceptor.handle(keyCode: keyCode, isDown: isDown, fine: fine) }
    return swallowed ? nil : Unmanaged.passUnretained(event)
}
