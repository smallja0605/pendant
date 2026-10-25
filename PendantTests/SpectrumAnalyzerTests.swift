import Foundation
import Testing
@testable import Pendant

struct SpectrumAnalyzerTests {
    private func sine(_ hertz: Double, rate: Double = 48_000, amplitude: Float = 0.5) -> [Float] {
        (0..<SpectrumAnalyzer.size).map { amplitude * Float(sin(2 * .pi * hertz * Double($0) / rate)) }
    }

    private func levels(_ samples: [Float], bands: Int, rate: Double = 48_000) -> [Float] {
        samples.withUnsafeBufferPointer { SpectrumAnalyzer().levels(samples: $0.baseAddress!, sampleRate: rate, bands: bands) }
    }

    @Test func silenceGivesFlatBars() {
        #expect(levels([Float](repeating: 0, count: SpectrumAnalyzer.size), bands: 5).allSatisfy { $0 == 0 })
    }

    @Test func aToneLightsTheBandItBelongsTo() {
        for bands in [3, 5, 7] {
            let ratio = pow(SpectrumAnalyzer.highestHz / SpectrumAnalyzer.lowestHz, 1 / Double(bands))
            for band in 0..<bands {
                // A tone at the middle of a band (a tone right on an edge may fairly belong to either neighbour).
                let hertz = SpectrumAnalyzer.lowestHz * pow(ratio, Double(band) + 0.5)
                let result = levels(sine(hertz), bands: bands)
                #expect(result.firstIndex(of: result.max() ?? 0) == band, "\(Int(hertz)) Hz with \(bands) bars")
                #expect((result.max() ?? 0) > 0.4)
            }
        }
    }

    @Test func louderMeansHigher() {
        let quiet = levels(sine(1_000, amplitude: 0.01), bands: 3).max() ?? 0
        let loud = levels(sine(1_000, amplitude: 0.5), bands: 3).max() ?? 0
        #expect(loud > quiet)
    }

    @Test func bandsAreOrderedAndDoNotOverlap() {
        for bands in 3...7 {
            for rate in [44_100.0, 48_000.0, 96_000.0] {
                let ranges = SpectrumAnalyzer.bandBins(count: bands, sampleRate: rate)
                #expect(ranges.count == bands)
                for (left, right) in zip(ranges, ranges.dropFirst()) { #expect(left.upperBound < right.lowerBound || right.lowerBound == left.upperBound + 1) }
                #expect(ranges.allSatisfy { $0.upperBound < SpectrumAnalyzer.size / 2 })
            }
        }
    }
}
