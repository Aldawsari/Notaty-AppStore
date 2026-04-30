import SwiftUI

/// Sticky banner shown at the top of the note window when the user has dropped
/// one or more files on the menu bar icon and hasn't yet picked a destination
/// note. Lists each file in the shelf so the user can see exactly what will
/// attach when they click a tab.
struct MenuBarDropBanner: View {
    let urls: [URL]
    let onCancel: () -> Void
    let onRemove: (URL) -> Void

    private var headerText: String {
        if urls.count == 1 { return "Attaching \(urls[0].lastPathComponent)" }
        return "Attaching \(urls.count) files"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text(headerText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel all")
            }

            // List each file in the shelf with a per-file × to remove just
            // that one. Show the list whenever there's at least one file —
            // single file already named in the header gets a row with size
            // and remove button for symmetry.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(urls, id: \.self) { url in
                    fileRow(for: url)
                }
            }
            .padding(.leading, 23)

            Text("Click a tab to attach, or ＋ for a new note")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 23)
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

    @ViewBuilder
    private func fileRow(for url: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Text(url.lastPathComponent)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button(action: { onRemove(url) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Remove \(url.lastPathComponent) from shelf")
        }
    }
}
