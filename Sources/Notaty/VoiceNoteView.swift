import SwiftUI

struct VoiceNoteView: View {
    let noteID: UUID
    @ObservedObject private var store = NotesStore.shared
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()
    @State private var isTranscribing = false
    @State private var transcriptionText = ""
    @State private var showTranscription = false

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

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    private var transcriptionDirection: LayoutDirection {
        let direction = NoteTextEditor.resolveDirection(mode: .auto, text: transcriptionText)
        return direction == .rightToLeft ? .rightToLeft : .leftToRight
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

            // Transcribing indicator
            if isTranscribing {
                Divider()
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Transcribing...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }

            // Transcription bubble (toggle on/off)
            if showTranscription && !transcriptionText.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Voice Transcription")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: copyTranscriptionToNote) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to note")
                    }

                    Text(transcriptionText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, transcriptionDirection)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.06))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            // Text editor for notes
            NoteTextEditor(
                text: store.textBinding(for: noteID),
                directionMode: note?.direction ?? .auto
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !hasAudio && !recorder.isRecording {
                startRecording()
            }
        }
        .onDisappear {
            if recorder.isRecording {
                _ = recorder.stopRecording()
            }
            player.stop()
            appDelegate?.suppressDismiss = false
        }
        .onChange(of: recorder.isRecording) { recording in
            appDelegate?.suppressDismiss = recording || isTranscribing
        }
        .onChange(of: isTranscribing) { transcribing in
            appDelegate?.suppressDismiss = recorder.isRecording || transcribing
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

            Text("Recording...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text(formatTime(recorder.elapsedTime))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: stopRecordingAction) {
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

            // Waveform
            if let url = audioURL {
                WaveformView(
                    audioURL: url,
                    progress: player.duration > 0 ? player.currentTime / player.duration : 0
                )
                .frame(height: 32)
                .contentShape(Rectangle())
                .overlay(
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard player.duration > 0 else { return }
                                        let ratio = max(0, min(1, value.location.x / geo.size.width))
                                        player.seek(to: ratio * player.duration)
                                    }
                            )
                    }
                )
            }

            Text(formatTime(player.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            // Transcribe toggle button
            if !isTranscribing {
                Button(action: toggleTranscription) {
                    Image(systemName: showTranscription ? "text.badge.minus" : "text.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(showTranscription ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .help(showTranscription ? "Hide transcription" : "Transcribe")
            }
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
                Label("Start Recording", systemImage: "mic.fill")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func startRecording() {
        guard let url = audioURL else { return }
        appDelegate?.suppressDismiss = true
        playSound("Tink")
        recorder.startRecording(to: url)
    }

    private func stopRecordingAction() {
        playSound("Pop")
        _ = recorder.stopRecording()
        guard let url = audioURL, FileManager.default.fileExists(atPath: url.path) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            player.load(url: url)

            if Settings.shared.autoTranscribe {
                toggleTranscription()
            } else {
                appDelegate?.suppressDismiss = false
            }
        }
    }

    private func toggleTranscription() {
        if showTranscription {
            // Hide
            showTranscription = false
        } else if !transcriptionText.isEmpty {
            // Already transcribed — just show
            showTranscription = true
        } else {
            // Need to transcribe first
            transcribeAudio()
        }
    }

    private func transcribeAudio() {
        guard let url = audioURL, FileManager.default.fileExists(atPath: url.path) else { return }

        appDelegate?.suppressDismiss = true
        isTranscribing = true
        showTranscription = true
        Task {
            do {
                let text = try await SpeechTranscriber.transcribe(audioURL: url)
                await MainActor.run {
                    transcriptionText = text
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    print("Transcription error: \(error)")
                    isTranscribing = false
                    showTranscription = false
                }
            }
        }
    }

    private func copyTranscriptionToNote() {
        let separator = "━━━━━━━━━━━━━━━━━━━━"
        let block = "\(separator)\n🎙✍️ Transcription\n\(separator)\n\(transcriptionText)\n\(separator)\n\n"
        store.update(id: noteID) {
            $0.text = block + $0.text
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
