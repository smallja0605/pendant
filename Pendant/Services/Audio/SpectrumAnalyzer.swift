import Accelerate
import Foundation

/// Turns a block of audio samples into a few bar heights: a Hann-windowed FFT, the energy of each of `bands` logarithmically spaced
/// frequency bands (low notes on the left, high on the right), on a decibel scale from quiet to loud, 0…1. Pure maths, no audio
/// device: the tap in `AudioSpectrum` feeds it.
final class SpectrumAnalyzer {
    static let size = 2048
    /// Band range, Hz: below this there is mostly rumble, above it the top of what a small bar can show.
    static let lowestHz = 70.0
    static let highestHz = 9000.0
    /// Loudness range of a band (dB relative to full scale) mapped to 0…1.
    static let floorDB: Float = -78
    static let ceilingDB: Float = -34

    private let log2n: vDSP_Length
    private let setup: FFTSetup?
    private let window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var windowed: [Float]
    private var power: [Float]

    init() {
        let length = Self.size
        log2n = vDSP_Length(log2(Double(length)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        var hann = [Float](repeating: 0, count: length)
        vDSP_hann_window(&hann, vDSP_Length(length), Int32(vDSP_HANN_NORM))
        window = hann
        real = [Float](repeating: 0, count: length / 2)
        imag = [Float](repeating: 0, count: length / 2)
        windowed = [Float](repeating: 0, count: length)
        power = [Float](repeating: 0, count: length / 2)
    }

    deinit { if let setup { vDSP_destroy_fftsetup(setup) } }

    /// First and last FFT bin (inclusive) of each band.
    static func bandBins(count: Int, sampleRate: Double) -> [ClosedRange<Int>] {
        let binWidth = sampleRate / Double(size)
        let top = Double(size / 2 - 1)
        let ratio = pow(highestHz / lowestHz, 1 / Double(count))
        var result: [ClosedRange<Int>] = []
        var lower = max(Int((lowestHz / binWidth).rounded()), 1)
        for index in 1...count {
            let edge = lowestHz * pow(ratio, Double(index))
            var upper = min(Int((edge / binWidth).rounded()) - 1, Int(top))
            upper = max(upper, lower)
            result.append(lower...upper)
            lower = min(upper + 1, Int(top))
        }
        return result
    }

    /// `samples` holds `Self.size` mono samples (-1…1). Returns `bands` values in 0…1.
    func levels(samples: UnsafePointer<Float>, sampleRate: Double, bands: Int) -> [Float] {
        let length = Self.size
        guard let setup else { return [Float](repeating: 0, count: bands) }
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(length))
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        windowed.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            base.withMemoryRebound(to: DSPComplex.self, capacity: length / 2) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(length / 2))
            }
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(length / 2))
        // vDSP's real FFT is scaled by 2, the window by its energy: this brings a full-scale sine to about 0 dB.
        let scale: Float = 1 / Float(length * length) * 4
        var result = [Float](repeating: 0, count: bands)
        for (index, range) in Self.bandBins(count: bands, sampleRate: sampleRate).enumerated() {
            var sum: Float = 0
            for bin in range { sum += power[bin] * scale }
            let mean = sum / Float(range.count)
            // Treble holds less energy than bass in real music: a gentle lift per band keeps the right bars alive.
            let tilt = 1.5 * Float(index) * (6 / Float(max(bands, 2)))
            let decibels = 10 * log10(max(mean, 1e-12)) + tilt
            result[index] = min(max((decibels - Self.floorDB) / (Self.ceilingDB - Self.floorDB), 0), 1)
        }
        return result
    }
}
