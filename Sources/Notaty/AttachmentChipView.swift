import SwiftUI
import AppKit
import ImageIO

struct AttachmentChipView: View {
    let attachment: Attachment
    let onRemove: () -> Void
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var isHovering: Bool = false
    @State private var pendingSingleClick: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 8) {
            // Gesture-receiving inner content (thumbnail + name/size).
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
            }
            .contentShape(Rectangle())
            .gesture(
                ExclusiveGesture(
                    TapGesture(count: 2).onEnded {
                        pendingSingleClick?.cancel()
                        pendingSingleClick = nil
                        onDoubleClick()
                    },
                    TapGesture(count: 1).onEnded {
                        let work = DispatchWorkItem { onSingleClick() }
                        pendingSingleClick = work
                        let delay = NSEvent.doubleClickInterval
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                    }
                )
            )

            // × button — sibling of the gesture-receiving HStack, NOT a child.
            // This is the structural fix for the bug: the parent gesture
            // does not extend over the × button's frame, so clicking ×
            // only fires the Button's action, never the parent gesture.
            if isHovering {
                Button(action: {
                    pendingSingleClick?.cancel()
                    pendingSingleClick = nil
                    onRemove()
                }) {
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
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if attachment.isImage, let nsImage = imageThumbnail {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            typeIcon
        }
    }

    /// Decode a small thumbnail from the on-disk file. We bypass NSImage's
    /// default behavior of loading the full image by using ImageIO to ask
    /// for a thumbnail of the right pixel size. Returns nil for non-image
    /// files or decode failures.
    private var imageThumbnail: NSImage? {
        let url = NotesStore.attachmentURL(for: attachment)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 56,  // 28pt @2x
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 28, height: 28))
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
