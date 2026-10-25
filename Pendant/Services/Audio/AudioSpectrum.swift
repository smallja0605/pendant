import AudioToolbox
import CoreAudio
import Foundation
import os

/// The real sound as bar heights: a Core Audio "process tap" copies what the Mac is playing (nothing is recorded or stored — each block
/// is turned into a few numbers and dropped), `SpectrumAnalyzer` makes the bands. Runs only while a waveform is on screen, the music is
/// playing and the setting is on. macOS asks for the "system audio recording" permission the first time.
@available(macOS 14.2, *)
final class AudioSpectrum: @unchecked Sendable {
    static let shared = AudioSpectrum()

    enum Status: Equatable { case off, starting, running, failed(String) }

    private struct Shared {
        var levels: [Float] = []
        var bands = 3
        var status = Status.off
        var lastSound = Date.distantPast
        var startedAt = Date.distantPast
    }

    private let lock = OSAllocatedUnfairLock(initialState: Shared())
    private var owners = Set<UUID>()
    private let queue = DispatchQueue(label: "pendant.audio-spectrum", qos: .userInteractive)

    // Core Audio objects, touched only on `queue`.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var running = false
    private let analyzer = SpectrumAnalyzer()
    private var ring = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var ringCount = 0
    private var sampleRate = 48_000.0
    private var smoothed: [Float] = []
    /// Each band's average level over about a second: bars show a band relative to it, so a drum hit stands out from the steady sound.
    private var averages: [Float] = []
    private var outputListenerInstalled = false

    // MARK: Reading (any thread)

    var status: Status { lock.withLock { $0.status } }

    /// No sound arrived for a while although it was asked for: most likely the permission is missing.
    var seemsSilent: Bool {
        lock.withLock { shared in
            let now = Date()
            return shared.status == .running && now.timeIntervalSince(shared.startedAt) > 4 && now.timeIntervalSince(shared.lastSound) > 4
        }
    }

    /// `count` values in 0…1 (all 0 while nothing plays).
    func levels(count: Int) -> [Float] {
        lock.withLock { shared in
            shared.bands = count
            return shared.levels.count == count ? shared.levels : [Float](repeating: 0, count: count)
        }
    }

    // MARK: Starting and stopping

    /// A view that shows a waveform asks for the sound (`wanted`) or lets it go; the tap runs while anyone wants it.
    func setWanted(_ wanted: Bool, owner: UUID) {
        queue.async { [self] in
            if wanted { owners.insert(owner) } else { owners.remove(owner) }
            if owners.isEmpty { stop() } else if !running { start() }
        }
    }

    private func start() {
        guard !running else { return }
        lock.withLock { $0.status = .starting; $0.startedAt = Date(); $0.lastSound = .distantPast }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Pendant waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return fail("無法讀取系統音訊") }
        tapID = tap

        guard let outputUID = Self.defaultOutputUID() else { return teardown(fail: "找不到輸出裝置") }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pendant waveform",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else { return teardown(fail: "無法建立音訊裝置") }
        aggregateID = device

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
        }
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        ringCount = 0
        smoothed = []
        averages = []

        var proc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input, interleaved: interleaved)
        }
        guard created == noErr, let proc else { return teardown(fail: "無法讀取系統音訊") }
        procID = proc
        guard AudioDeviceStart(aggregateID, proc) == noErr else { return teardown(fail: "無法開始讀取音訊") }
        running = true
        lock.withLock { $0.status = .running }
        installOutputListener()
    }

    private func stop() {
        guard running || tapID != kAudioObjectUnknown else { return }
        teardown(fail: nil)
        lock.withLock { $0.status = .off; $0.levels = [] }
    }

    private func fail(_ message: String) {
        teardown(fail: message)
    }

    private func teardown(fail message: String?) {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        running = false
        if let message { lock.withLock { $0.status = .failed(message); $0.levels = [] } }
    }

    /// The tap is tied to the output device that was current when it started: when that changes (headphones plugged in, AirPlay),
    /// start over on the new one.
    private func installOutputListener() {
        guard !outputListenerInstalled else { return }
        outputListenerInstalled = true
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue) { [weak self] _, _ in
            guard let self, running else { return }
            teardown(fail: nil)
            if !owners.isEmpty { start() }
        }
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    // MARK: The audio callback (on `queue`)

    private func consume(_ input: UnsafePointer<AudioBufferList>, interleaved: Bool) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let base = first.mData?.assumingMemoryBound(to: Float.self) else { return }
        let channels = interleaved ? max(Int(first.mNumberChannels), 1) : 1
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        let size = SpectrumAnalyzer.size
        for frame in 0..<frames {
            var mixed: Float = 0
            if interleaved {
                for channel in 0..<channels { mixed += base[frame * channels + channel] }
                mixed /= Float(channels)
            } else {
                var count: Float = 0
                for buffer in buffers {
                    if let data = buffer.mData?.assumingMemoryBound(to: Float.self) { mixed += data[frame]; count += 1 }
                }
                mixed /= max(count, 1)
            }
            ring[ringCount] = mixed
            ringCount += 1
            if ringCount == size {
                analyze()
                // Overlap by half a block: about a hundred updates a second.
                ring.withUnsafeMutableBufferPointer { buffer in
                    for index in 0..<size / 2 { buffer[index] = buffer[index + size / 2] }
                }
                ringCount = size / 2
            }
        }
    }

    private func analyze() {
        let bands = lock.withLock { $0.bands }
        let raw = ring.withUnsafeBufferPointer { buffer -> [Float] in
            guard let base = buffer.baseAddress else { return [Float](repeating: 0, count: bands) }
            return analyzer.levels(samples: base, sampleRate: sampleRate, bands: bands)
        }
        if smoothed.count != bands {
            smoothed = [Float](repeating: 0, count: bands)
            averages = [Float](repeating: 0, count: bands)
        }
        for index in 0..<bands {
            // Relative to the band's own average: steady sound sits at about half height and a beat (a kick, a snare) climbs from there,
            // instead of every bar sitting at the top. Near-silence is not blown up (the floor).
            averages[index] += (raw[index] - averages[index]) * 0.015
            let scaled = min(0.5 * raw[index] / max(averages[index], 0.08), 1)
            // Rises quickly, falls slowly: bars follow a beat without flickering.
            let rate: Float = scaled > smoothed[index] ? 0.7 : 0.2
            smoothed[index] += (scaled - smoothed[index]) * rate
        }
        let sound = raw.contains { $0 > 0.02 }
        let levels = smoothed
        lock.withLock { shared in
            shared.levels = levels
            if sound { shared.lastSound = Date() }
        }
    }
}
