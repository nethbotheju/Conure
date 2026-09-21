import Foundation
import AudioCommon

public enum SampleRate {
    public static let mono16k = 16000
}

public enum AudioDecoder {
    public static func loadMono16k(from url: URL) throws -> [Float] {
        try AudioFileLoader.load(url: url, targetSampleRate: SampleRate.mono16k)
    }

    public static func duration(of samples: [Float], sampleRate: Int = SampleRate.mono16k) -> Double {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / Double(sampleRate)
    }

    public static func slice(_ samples: [Float], from start: Double, to end: Double, sampleRate: Int) -> ArraySlice<Float> {
        let lower = max(0, min(samples.count, Int(start * Double(sampleRate))))
        let upper = max(lower, min(samples.count, Int(end * Double(sampleRate))))
        return samples[lower..<upper]
    }
}
