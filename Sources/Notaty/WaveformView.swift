import SwiftUI
import AVFoundation

/// Extracts amplitude samples from an audio file and renders a smooth waveform curve.
struct WaveformView: View {
    let audioURL: URL
    let progress: Double // 0...1
    var sampleCount: Int = 80

    @State private var samples: [Float] = []

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mid = h / 2

            if !samples.isEmpty {
                // Played portion
                SmoothWavePath(samples: samples, width: w, height: h)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .clipShape(Rectangle().size(width: w * progress, height: h))

                // Unplayed portion
                SmoothWavePath(samples: samples, width: w, height: h)
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .clipShape(Rectangle().offset(x: w * progress).size(width: w * (1 - progress), height: h))
            } else {
                // Placeholder center line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: mid))
                    path.addLine(to: CGPoint(x: w, y: mid))
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onAppear { loadSamples() }
    }

    private func loadSamples() {
        DispatchQueue.global(qos: .userInitiated).async {
            let extracted = Self.extractSamples(from: audioURL, count: sampleCount)
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
                result[i] = max(0.03, result[i] / maxPeak)
            }
        }

        return result
    }
}

/// Draws a smooth Catmull-Rom spline through amplitude sample points.
private struct SmoothWavePath: Shape {
    let samples: [Float]
    let width: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        guard samples.count >= 2 else { return Path() }

        let mid = height / 2
        let points: [CGPoint] = samples.enumerated().map { i, amp in
            let x = width * CGFloat(i) / CGFloat(samples.count - 1)
            let y = mid - CGFloat(amp) * mid * 0.9 // scale to 90% of half-height
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        path.move(to: points[0])

        for i in 0..<points.count - 1 {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            // Catmull-Rom to cubic Bezier control points
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        return path
    }
}
