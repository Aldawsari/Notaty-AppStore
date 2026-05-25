import Foundation
import Combine
import AppKit
import AVFoundation

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
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startAuthorizedRecording(in: noteID)
        case .notDetermined:
            requestMicrophoneAccess(for: noteID)
        case .denied, .restricted:
            showMicrophoneAccessAlert()
        @unknown default:
            showMicrophoneAccessAlert()
        }
    }

    @MainActor
    private func requestMicrophoneAccess(for noteID: UUID) {
        (NSApp.delegate as? AppDelegate)?.suppressDismiss = true
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                let appDelegate = NSApp.delegate as? AppDelegate
                appDelegate?.suppressDismiss = false
                if granted {
                    Self.shared.startAuthorizedRecording(in: noteID)
                } else {
                    Self.shared.showMicrophoneAccessAlert()
                }
            }
        }
    }

    @MainActor
    private func startAuthorizedRecording(in noteID: UUID) {
        guard !isActive else { return }
        NotesStore.shared.ensureAttachmentsDir()
        let storedName = "\(UUID().uuidString).m4a"
        let url = NotesStore.attachmentsDir.appendingPathComponent(storedName)

        do {
            try recorder.startRecording(to: url)
            currentNoteID = noteID
        } catch {
            currentNoteID = nil
            showRecordingStartError(error)
        }
    }

    @MainActor
    private func showMicrophoneAccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone access required"
        alert.informativeText = "Notaty needs microphone access to record voice notes. Enable it in System Settings, then try recording again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func showRecordingStartError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Recording failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
            byteSize: size,
            isVoiceNote: true
        )
        NotesStore.shared.update(id: noteID) { $0.attachments.append(attachment) }
        if Settings.shared.autoTranscribe {
            Task { @MainActor in
                await TranscriptCache.shared.transcribe(
                    storedName: storedName,
                    audioURL: url
                )
            }
        }
        return storedName
    }
}
