import Foundation

public enum LatchSynthesis {
    public static let sampleRate = 48_000

    /// Original, deterministic Foley: a damped impact, short release, and filtered noise.
    /// Audio is made in memory; no network, samples, or file writes are required.
    public static func samples(tone: LatchTone) -> [Float] {
        let duration = 0.22
        var noise: UInt32 = 0xD0011D
        var previousNoise = 0.0
        let base: Double = tone == .soft ? 155 : tone == .crisp ? 310 : 205
        let brightness: Double = tone == .soft ? 0.10 : tone == .crisp ? 0.34 : 0.22
        return (0..<Int(duration * Double(sampleRate))).map { index in
            let t = Double(index) / Double(sampleRate)
            noise = noise &* 1_664_525 &+ 1_013_904_223
            let white = Double(noise) / Double(UInt32.max) * 2 - 1
            previousNoise = previousNoise * 0.38 + white * 0.62
            let attack = 1 - exp(-t * 5_000)
            let body = sin(2 * .pi * base * t + 0.6 * exp(-t * 95)) * exp(-t * 62) * 0.55
            let snap = previousNoise * exp(-t * 260) * brightness
            let ring = sin(2 * .pi * 1_460 * t) * exp(-t * 110) * brightness * 0.28
            let delayed = max(0, t - 0.018)
            let release = t > 0.018 ? sin(2 * .pi * base * 1.45 * delayed) * exp(-delayed * 130) * 0.12 : 0
            let tail = min(1, max(0, (duration - t) / 0.015))
            return Float(max(-0.9, min(0.9, (body + snap + ring + release) * attack * tail)))
        }
    }

    public static func waveData(tone: LatchTone) -> Data {
        let pcm = samples(tone: tone)
        var data = Data()
        func appendText(_ value: String) { data.append(contentsOf: value.utf8) }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(pcm.count * 2)
        appendText("RIFF")
        append32(36 + byteCount)
        appendText("WAVEfmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        appendText("data")
        append32(byteCount)
        for sample in pcm { append16(UInt16(bitPattern: Int16(sample * 32_767))) }
        return data
    }
}
