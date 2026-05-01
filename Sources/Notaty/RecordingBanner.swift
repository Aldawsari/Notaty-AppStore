import SwiftUI

/// Slim red banner shown between the title row and the attachment strip while
/// a recording is active for the given note. Displays a pulsing dot, elapsed
/// timer, live amplitude waveform, and a Stop button. Renders nothing when
/// no recording is active or when this isn't the originating note.
struct RecordingBanner: View {
    let noteID: UUID
    @ObservedObject private var session = RecordingSession.shared
    @ObservedObject private var recorder = RecordingSession.shared.recorder

    var body: some View {
        if session.isActive, session.currentNoteID == noteID {
            content
        } else {
            EmptyView()
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            pulseDot
            Text(formattedElapsed)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundColor(.primary)
                .frame(minWidth: 32, alignment: .leading)
            waveform
                .frame(maxWidth: .infinity)
            stopButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 1.0, green: 0.96, blue: 0.96))
        .overlay(
            Rectangle()
                .fill(Color(red: 0.99, green: 0.79, blue: 0.79))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var pulseDot: some View {
        Circle()
            .fill(Color(red: 0.86, green: 0.15, blue: 0.15))
            .frame(width: 8, height: 8)
            // SwiftUI macOS 13: use .opacity animation for the pulse since
            // box-shadow keyframes aren't available cross-platform.
            .opacity(pulseOn ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseOn)
            .onAppear { pulseOn = true }
    }

    @State private var pulseOn = false

    private var waveform: some View {
        GeometryReader { geo in
            let levels = recorder.recentLevels
            let count = max(1, levels.count)
            let spacing: CGFloat = 1.5
            let availableWidth = geo.size.width
            let barWidth = max(1.5, (availableWidth - spacing * CGFloat(count - 1)) / CGFloat(40))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<levels.count, id: \.self) { i in
                    let amplitude = max(0.05, CGFloat(levels[i]))
                    Capsule()
                        .fill(Color(red: 0.86, green: 0.15, blue: 0.15))
                        .frame(width: barWidth, height: max(2, amplitude * geo.size.height))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 22)
    }

    private var stopButton: some View {
        Button(action: { _ = session.stop() }) {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .heavy))
                Text("Stop")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(red: 0.86, green: 0.15, blue: 0.15))
            )
        }
        .buttonStyle(.plain)
        .help("Stop recording")
    }

    private var formattedElapsed: String {
        let total = Int(recorder.elapsedTime)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
