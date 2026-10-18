import AppKit
import AudioToolbox
import CoreAudio

/// A change of the system output volume or of the built-in display's brightness.
enum SystemLevel: Equatable, Sendable {
    case volume(level: Double, muted: Bool)
    case brightness(level: Double)
}

/// Watches the system volume (CoreAudio property listeners on the default output device, no permission needed) and the
/// built-in display's brightness (`DisplayServices`, a private framework loaded at run time; it has no change notification
/// we can rely on, so it is read a few times a second, and only while the brightness HUD is on).
@MainActor
final class SystemLevelMonitor {
    var onChange: ((SystemLevel) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var lastVolume: Double?
    private var lastMuted = false
    private var brightnessTimer: Timer?
    private var lastBrightness: Double?
    private var started = false

    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663 // 'vmvc'
    private static var outputScope: AudioObjectPropertyScope { kAudioDevicePropertyScopeOutput }

    // MARK: Lifecycle

    func start(volume: Bool, brightness: Bool) {
        if volume { startVolume() } else { stopVolume() }
        if brightness { startBrightness() } else { stopBrightness() }
        started = volume || brightness
    }

    func stop() {
        stopVolume()
        stopBrightness()
        started = false
    }

    // MARK: Volume

    private func startVolume() {
        guard defaultDeviceListener == nil else { return }
        attachToDefaultDevice()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        defaultDeviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    private func stopVolume() {
        detachFromDevice()
        if let block = defaultDeviceListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
        defaultDeviceListener = nil
        lastVolume = nil
    }

    /// (Re)listens on the current default output device. Switching devices only records the new baseline: no HUD for it.
    private func attachToDefaultDevice() {
        detachFromDevice()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return }
        device = id
        lastVolume = readVolume()
        lastMuted = readMuted()
        for selector in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
            var property = AudioObjectPropertyAddress(
                mSelector: selector, mScope: Self.outputScope, mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(id, &property) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.volumeChanged() }
            }
            AudioObjectAddPropertyListenerBlock(id, &property, DispatchQueue.main, block)
            deviceListeners.append((property, block))
        }
    }

    private func detachFromDevice() {
        for (var address, block) in deviceListeners { AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, block) }
        deviceListeners.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func readVolume() -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: Self.virtualMainVolume, mScope: Self.outputScope, mElement: kAudioObjectPropertyElementMain
        )
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr { return Double(min(max(value, 0), 1)) }
        // No virtual main volume: average the channels (1 = left, 2 = right) that have a scalar volume.
        let channels = (1...2).compactMap { channel -> Double? in
            var channelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: Self.outputScope, mElement: AudioObjectPropertyElement(channel)
            )
            var channelValue = Float32(0)
            var channelSize = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &channelAddress, 0, nil, &channelSize, &channelValue) == noErr else { return nil }
            return Double(channelValue)
        }
        return channels.isEmpty ? nil : min(max(channels.reduce(0, +) / Double(channels.count), 0), 1)
    }

    private func readMuted() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: Self.outputScope, mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func volumeChanged() {
        guard let level = readVolume() else { return }
        let muted = readMuted()
        guard level != lastVolume || muted != lastMuted else { return }
        lastVolume = level
        lastMuted = muted
        onChange?(.volume(level: level, muted: muted))
    }

    // MARK: Changing the levels (when the media keys are intercepted)

    func currentVolume() -> Double? {
        if device == kAudioObjectUnknown { attachToDefaultDevice() }
        return readVolume()
    }

    func currentlyMuted() -> Bool { readMuted() }

    func setVolume(_ level: Double) {
        guard device != kAudioObjectUnknown else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: Self.virtualMainVolume, mScope: Self.outputScope, mElement: kAudioObjectPropertyElementMain
        )
        var value = Float32(min(max(level, 0), 1))
        if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr { return }
        for channel in 1...2 {
            var channelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: Self.outputScope, mElement: AudioObjectPropertyElement(channel)
            )
            AudioObjectSetPropertyData(device, &channelAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    func setMuted(_ muted: Bool) {
        guard device != kAudioObjectUnknown else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: Self.outputScope, mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    func currentBrightness() -> Double? { readBrightness() }

    func setBrightness(_ level: Double) {
        guard let writer = Self.brightnessWriter, let display = builtInDisplay() else { return }
        _ = writer(display, Float(min(max(level, 0), 1)))
    }

    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private static let brightnessWriter: SetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }()

    // MARK: Brightness

    private func startBrightness() {
        guard brightnessTimer == nil, Self.brightnessReader != nil else { return }
        lastBrightness = readBrightness()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBrightness() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        brightnessTimer = timer
    }

    private func stopBrightness() {
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        lastBrightness = nil
    }

    private func pollBrightness() {
        guard let level = readBrightness() else { return }
        defer { lastBrightness = level }
        // Ambient-light adjustment drifts by tiny steps; the keys (and the slider) jump by far more.
        guard let last = lastBrightness, abs(level - last) >= 0.012 else { return }
        onChange?(.brightness(level: level))
    }

    // `DisplayServicesGetBrightness(display, &value)`, looked up at run time (private framework; absent or changed → no HUD).
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    private static let brightnessReader: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private func builtInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(8, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func readBrightness() -> Double? {
        guard let reader = Self.brightnessReader, let display = builtInDisplay() else { return nil }
        var value = Float(0)
        guard reader(display, &value) == 0 else { return nil }
        return Double(min(max(value, 0), 1))
    }
}
