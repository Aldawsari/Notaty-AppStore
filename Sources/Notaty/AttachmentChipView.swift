import SwiftUI
import AppKit

struct AttachmentChipView: View {
    let attachment: Attachment
    let onRemove: () -> Void
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var isHovering: Bool = false
    @State private var pendingSingleClick: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.originalName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formattedSize)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove attachment")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick()
        }
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            let work = DispatchWorkItem { onSingleClick() }
            pendingSingleClick = work
            let delay = NSEvent.doubleClickInterval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        })
    }

    @ViewBuilder
    private var thumbnail: some View {
        // Image-thumbnail support is Task 7. For now everything uses the type icon.
        if attachment.isImage {
            typeIcon
        } else {
            typeIcon
        }
    }

    private var typeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(typeColor)
            Text(attachment.typeLabel)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        }
    }

    private var typeColor: Color {
        switch attachment.fileExtension {
        case "pdf":
            return Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x1C / 255.0)
        case "doc", "docx", "rtf":
            return Color(red: 0x1E / 255.0, green: 0x40 / 255.0, blue: 0xAF / 255.0)
        case "zip", "tar", "gz":
            return Color(red: 0x16 / 255.0, green: 0x65 / 255.0, blue: 0x34 / 255.0)
        case "m4a", "mp3", "wav", "aiff":
            return Color(red: 0x7C / 255.0, green: 0x3A / 255.0, blue: 0xED / 255.0)
        case "mp4", "mov":
            return Color(red: 0xEA / 255.0, green: 0x58 / 255.0, blue: 0x0C / 255.0)
        default:
            return Color(NSColor.systemGray)
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: attachment.byteSize, countStyle: .file)
    }
}
