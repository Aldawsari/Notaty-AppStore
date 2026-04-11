import AppKit
import SwiftUI
import Combine

final class QuickSwitcherState: ObservableObject {
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0

    var filtered: [Note] {
        let notes = NotesStore.shared.notes
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return notes }
        return notes.filter {
            $0.title.lowercased().contains(q) || $0.text.lowercased().contains(q)
        }
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func commit() -> UUID? {
        let list = filtered
        guard list.indices.contains(selectedIndex) else { return nil }
        return list[selectedIndex].id
    }
}

struct QuickSwitcherView: View {
    @ObservedObject var state: QuickSwitcherState
    let onPick: (UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find a note…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit {
                        if let id = state.commit() { onPick(id) } else { onCancel() }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    let list = state.filtered
                    if list.isEmpty {
                        Text("No notes match")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, note in
                            Row(note: note, isActive: index == state.selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.selectedIndex = index
                                    onPick(note.id)
                                }
                        }
                    }
                }
            }
            .frame(height: 280)
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .onChange(of: state.query) { _ in state.selectedIndex = 0 }
    }

    private struct Row: View {
        let note: Note
        let isActive: Bool

        private var title: String {
            let t = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Untitled" : t
        }

        private var preview: String {
            note.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.accentColor.opacity(0.25) : Color.clear)
        }
    }
}

final class QuickSwitcherWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: QuickSwitcherWindowController?

    private let state = QuickSwitcherState()
    private var keyMonitor: Any?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = QuickSwitcherWindowController()
        shared = controller
        controller.showWindow()
    }

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.appearance = Settings.shared.theme.nsAppearance

        self.init(window: panel)
        panel.delegate = self

        let view = QuickSwitcherView(
            state: state,
            onPick: { [weak self] id in
                NotesStore.shared.select(id)
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }
        )
        panel.contentViewController = NSHostingController(rootView: view)
    }

    private func showWindow() {
        state.query = ""
        state.selectedIndex = 0
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    private func dismiss() {
        window?.orderOut(nil)
        removeKeyMonitor()
        Self.shared = nil
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            switch event.keyCode {
            case 53: // escape
                self.dismiss()
                return nil
            case 125: // down arrow
                self.state.move(1)
                return nil
            case 126: // up arrow
                self.state.move(-1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
        Self.shared = nil
    }
}
