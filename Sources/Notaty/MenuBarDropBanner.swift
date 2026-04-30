import SwiftUI

/// Sticky banner shown at the top of the note window when the user has dropped
/// a file on the menu bar icon and hasn't yet picked a destination note.
struct MenuBarDropBanner: View {
    let description: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperclip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Attaching \(description)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Text("Click a tab to choose, or ＋ for a new note")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel attaching")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.18))
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
