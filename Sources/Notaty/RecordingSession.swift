import Foundation
import Combine

/// Global coordinator for the in-progress voice recording. Only one recording
/// can be active across the whole app (the mic is a singleton resource).
/// Exposes `isActive` and `currentNoteID` so views can:
///   - disable all 🎤 buttons + ⇧⌘N while a recording is active
///   - render the banner only on the originating note
final class RecordingSession: ObservableObject {
    static let shared = RecordingSession()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentNoteID: UUID? = nil

    /// The underlying recorder. Banner observes this for elapsed time and
    /// recentLevels (live waveform).
    let recorder = AudioRecorder()

    private var cancellable: AnyCancellable?

    private init() {
        // Mirror the recorder's isRecording into our isActive so observers
        // outside this class don't need to reach into the recorder.
        cancellable = recorder.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.isActive = recording
                if !recording { self?.currentNoteID = nil }
            }
    }

    /// Start a new recording targeted at the given note. If a recording is
    /// already active, this is a no-op (the global lock prevents concurrent
    /// recordings, but defend the API anyway).
    @MainActor
    func start(in noteID: UUID) {
        guard !isActive else { return }
        NotesStore.shared.ensureAttachmentsDir()
        let storedName = "\(UUID().uuidString).m4a"
        let url = NotesStore.attachmentsDir.appendingPathComponent(storedName)
        currentNoteID = noteID
        recorder.startRecording(to: url)
    }

    /// Stop the active recording. Finalizes the file, builds an Attachment
    /// record, and appends it to the originating note. Returns the new
    /// attachment's storedName on success, nil on failure.
    @MainActor
    @discardableResult
    func stop() -> String? {
        // Capture noteID locally before stopRecording(): stopRecording sets
        // recorder.isRecording = false synchronously, which fires the Combine
        // sink that nullifies currentNoteID. The sink hops via DispatchQueue.main
        // (always async-deferred), so currentNoteID is still valid when read here,
        // but the local binding makes us robust if that hop is ever removed.
        guard isActive, let noteID = currentNoteID else { return nil }
        guard let url = recorder.stopRecording() else { return nil }
        let storedName = url.lastPathComponent
        let originalName = "Recording.m4a"
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let attachment = Attachment(
            originalName: originalName,
            storedName: storedName,
            byteSize: size
        )
        NotesStore.shared.update(id: noteID) { $0.attachments.append(attachment) }
        return storedName
    }
}
