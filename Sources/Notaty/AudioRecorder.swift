import AVFoundation
import Combine

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?

    func startRecording(to url: URL) {
        NotesStore.shared.ensureAudioDir()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            isRecording = true
            startTime = Date()
            elapsedTime = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        } catch {
            print("AudioRecorder: failed to start — \(error)")
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
            print("AudioRecorder: recording finished unsuccessfully")
        }
    }
}
