import SwiftUI
import AppKit
import ImageIO

struct AttachmentChipView: View {
    let attachment: Attachment
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onShowInFinder: () -> Void

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
                    TapGesture(count: 2).onEnded { onOpen() },
                    TapGesture(count: 1).onEnded { onSelect() }
                )
            )

            // × button — always visible, sibling of the gesture-receiving HStack.
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color(NSColor.separatorColor),
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Show in Finder") { onShowInFinder() }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
        }
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

    private var imageThumbnail: NSImage? {
        let url = NotesStore.attachmentURL(for: attachment)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 56,
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
