import AVFoundation
import Combine

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    /// Most recent normalized amplitude samples (0...1), one per metering tick.
    /// The banner's live waveform reads this; capped at the most recent 40
    /// samples so memory stays bounded for long recordings.
    @Published var recentLevels: [Float] = []

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private static let levelWindowSize = 40
    private static let meteringInterval: TimeInterval = 0.05

    func startRecording(to url: URL) {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()
            isRecording = true
            startTime = Date()
            elapsedTime = 0
            recentLevels = []
            timer = Timer.scheduledTimer(withTimeInterval: Self.meteringInterval, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } catch {
            NSLog("AudioRecorder: failed to start — \(error)")
        }
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        // averagePower returns dB, roughly -160 (silence) to 0 (full scale).
        // Normalize -60..0 → 0..1 so quiet rooms still produce visible bars.
        let dB = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (dB + 60) / 60))
        recentLevels.append(normalized)
        if recentLevels.count > Self.levelWindowSize {
            recentLevels.removeFirst(recentLevels.count - Self.levelWindowSize)
        }
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        isRecording = false
        return url
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            NSLog("AudioRecorder: recording finished unsuccessfully")
        }
    }
}
