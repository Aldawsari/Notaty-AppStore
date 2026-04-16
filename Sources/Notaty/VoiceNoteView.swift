import SwiftUI

struct VoiceNoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()
    @State private var isTranscribing = false

    private var note: Note? {
        store.note(for: noteID)
    }

    private var audioURL: URL? {
        guard let note else { return nil }
        return NotesStore.audioURL(for: note)
    }

    private var hasAudio: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var layoutDirection: LayoutDirection {
        let mode = note?.direction ?? .auto
        let text = note?.text ?? ""
        let direction = NoteTextEditor.resolveDirection(mode: mode, text: text)
        return direction == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title field
            TextField("Untitled", text: store.titleBinding(for: noteID))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .environment(\.layoutDirection, layoutDirection)

            Divider()

            // Audio control bar
            if recorder.isRecording {
                recordingBar
            } else if hasAudio {
                playerBar
            } else {
                readyToRecordBar
            }

            Divider()

            // Transcribing indicator
            if isTranscribing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("جاري التفريغ...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

                Divider()
            }

            // Transcription text editor
            NoteTextEditor(
                text: store.textBinding(for: noteID),
                directionMode: note?.direction ?? .auto
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear {
            if recorder.isRecording {
                _ = recorder.stopRecording()
            }
            player.stop()
        }
    }

    // MARK: - Recording Bar

    private var recordingBar: some View {
        HStack(spacing: 10) {
            // Pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(recorder.isRecording ? 1.0 : 0.3)
                .animation(
                    Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: recorder.isRecording
                )

            Text("جاري التسجيل...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text(formatTime(recorder.elapsedTime))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: stopAndTranscribe) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Stop recording")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Player Bar

    private var playerBar: some View {
        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause" : "Play")

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)

                    let progress = player.duration > 0 ? player.currentTime / player.duration : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(progress), height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = max(0, min(1, value.location.x / geo.size.width))
                            player.seek(to: ratio * player.duration)
                        }
                )
            }
            .frame(height: 20)

            Text(formatTime(player.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            if let url = audioURL {
                player.load(url: url)
            }
        }
    }

    // MARK: - Ready to Record Bar

    private var readyToRecordBar: some View {
        HStack {
            Spacer()
            Button(action: startRecording) {
                Label("ابدأ التسجيل", systemImage: "mic.fill")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func startRecording() {
        guard let url = audioURL else { return }
        recorder.startRecording(to: url)
    }

    private func stopAndTranscribe() {
        guard let url = recorder.stopRecording() else { return }

        // Load audio into player
        player.load(url: url)

        // Transcribe
        isTranscribing = true
        Task {
            do {
                let text = try await SpeechTranscriber.transcribe(audioURL: url)
                await MainActor.run {
                    store.update(id: noteID) { $0.text = text }
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                }
            }
        }
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            if let url = audioURL, player.duration == 0 {
                player.load(url: url)
            }
            player.play()
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
