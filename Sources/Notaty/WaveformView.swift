import SwiftUI
import AVFoundation

/// Extracts amplitude samples from an audio file and renders a thin bar waveform.
struct WaveformView: View {
    let audioURL: URL
    let progress: Double // 0...1
    var barCount: Int = 60

    @State private var samples: [Float] = []

    var body: some View {
        GeometryReader { geo in
            let count = samples.isEmpty ? barCount : samples.count
            let spacing: CGFloat = 1.5
            let barWidth = max(1, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let maxHeight = geo.size.height

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let amplitude = samples.isEmpty ? 0.15 : CGFloat(samples[i])
                    let height = max(2, amplitude * maxHeight)
                    let played = Double(i) / Double(max(1, count - 1)) <= progress

                    RoundedRectangle(cornerRadius: 1)
                        .fill(played ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
        }
        .onAppear { loadSamples() }
    }

    private func loadSamples() {
        DispatchQueue.global(qos: .userInitiated).async {
            let extracted = Self.extractSamples(from: audioURL, count: barCount)
            DispatchQueue.main.async {
                self.samples = extracted
            }
        }
    }

    /// Read audio file and downsample to `count` amplitude values (0...1).
    static func extractSamples(from url: URL, count: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }

        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: totalFrames)
        else { return [] }

        do {
            try file.read(into: buffer)
        } catch {
            return []
        }

        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameCount = Int(buffer.frameLength)

        var result = [Float](repeating: 0, count: count)
        let chunkSize = max(1, frameCount / count)

        for i in 0..<count {
            let start = i * chunkSize
            let end = min(start + chunkSize, frameCount)
            var peak: Float = 0
            for j in start..<end {
                let val = abs(channelData[j])
                if val > peak { peak = val }
            }
            result[i] = peak
        }

        let maxPeak = result.max() ?? 1
        if maxPeak > 0 {
            for i in 0..<count {
                result[i] = max(0.05, result[i] / maxPeak)
            }
        }

        return result
    }
}
