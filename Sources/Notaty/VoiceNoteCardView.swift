import SwiftUI
import AppKit

/// One row in `VoiceNoteStripView` — a player bar plus an optional
/// collapsible transcript bubble for a single voice-note Attachment.
struct VoiceNoteCardView: View {
    let attachment: Attachment
    let noteID: UUID
    /// 0-based position among the parent note's voice-note attachments.
    /// Renders as "Voice Note \(index + 1)" in the top-left label, the
    /// transcription bubble header, and the copy-to-note block.
    let index: Int

    @ObservedObject private var store = NotesStore.shared
    @ObservedObject private var cache = TranscriptCache.shared
    @StateObject private var player = AudioPlayer()
    @State private var showTranscription = false
    @State private var didLoadAudio = false

    private var audioURL: URL { NotesStore.attachmentURL(for: attachment) }
    private var displayName: String { "Voice Note \(index + 1)" }

    private var transcriptState: TranscriptCache.State {
        cache.state(for: attachment.storedName)
    }

    /// Whether the bubble is rendered. We hide it when transcript state is
    /// .idle (nothing to show) regardless of `showTranscription`, since the
    /// bubble would otherwise flash on first transcribe-tap before the
    /// loading state is set.
    private var bubbleVisible: Bool {
        guard showTranscription else { return false }
        switch transcriptState {
        case .idle: return false
        case .loading, .ready, .failed: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            playerBar
            if bubbleVisible {
                Divider().opacity(0.4)
                bubble
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .onAppear {
            if !didLoadAudio {
                player.load(url: audioURL)
                didLoadAudio = true
            }
        }
        .onDisappear { player.pause() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Player bar

    private var playerBar: some View {
        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause" : "Play")

            WaveformView(
                audioURL: audioURL,
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

            Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: handleTranscribeTap) {
                Image(systemName: transcribeIconName)
                    .font(.system(size: 14))
                    .foregroundColor(transcribeIconColor)
            }
            .buttonStyle(.plain)
            .disabled(transcriptState.isLoading)
            .help(transcribeHelpText)

            Button(action: confirmDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete voice note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript bubble

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("\(displayName) — Transcription")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if case .ready = transcriptState {
                    Button(action: copyTranscriptionToNote) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to note")
                }
            }
            bubbleBody
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        switch transcriptState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Transcribing…")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        case .ready(let text):
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, transcriptDirection(text))
        case .failed(let error):
            Text("Couldn't transcribe — \(error.localizedDescription)")
                .font(.system(size: 12))
                .foregroundColor(.red)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Icon resolution

    private var transcribeIconName: String {
        switch transcriptState {
        case .ready:
            return showTranscription ? "text.badge.minus" : "text.badge.plus"
        case .idle, .loading, .failed:
            return "text.badge.plus"
        }
    }

    private var transcribeIconColor: Color {
        switch transcriptState {
        case .loading: return Color.secondary.opacity(0.5)
        case .ready where showTranscription: return .secondary
        case .ready: return .accentColor
        case .idle, .failed: return .accentColor
        }
    }

    private var transcribeHelpText: String {
        switch transcriptState {
        case .idle: return "Transcribe"
        case .loading: return "Transcribing…"
        case .ready: return showTranscription ? "Hide transcription" : "Show transcription"
        case .failed: return "Try again"
        }
    }

    // MARK: - Actions

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            VoicePlaybackCoordinator.shared.didStartPlaying(player)
            player.play()
        }
    }

    private func handleTranscribeTap() {
        switch transcriptState {
        case .idle, .failed:
            showTranscription = true
            Task {
                await cache.transcribe(storedName: attachment.storedName, audioURL: audioURL)
            }
        case .ready:
            showTranscription.toggle()
        case .loading:
            break
        }
    }

    private func copyTranscriptionToNote() {
        guard case .ready(let text) = transcriptState else { return }
        let separator = "━━━━━━━━━━━━━━━━━━━━"
        let block = "\(separator)\n🎙✍️ \(displayName) — Transcription\n\(separator)\n\(text)\n\(separator)\n\n"
        store.update(id: noteID) { $0.text = block + $0.text }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete this voice note?"
        alert.informativeText = "The recording will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        cache.clear(storedName: attachment.storedName)
        store.removeAttachment(attachment.id, from: noteID)
    }

    // MARK: - Helpers

    private func transcriptDirection(_ text: String) -> LayoutDirection {
        let dir = NoteTextEditor.resolveDirection(mode: .auto, text: text)
        return dir == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private extension TranscriptCache.State {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
