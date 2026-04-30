import AppKit
import SwiftUI

/// A titlebar accessory hosting the pin button. Sits on the right side of the
/// note window's titlebar (next to the title), giving one-click access to
/// toggle `Settings.shared.pinned` regardless of where the user's focus is.
///
/// Replaces the old in-tab-bar pin button. Window-state controls live in
/// the window chrome, not in the content area.
final class PinTitlebarAccessoryViewController: NSTitlebarAccessoryViewController {

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
        let host = NSHostingView(rootView: PinTitlebarButton())
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        view.frame.size = CGSize(width: 32, height: 22)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private struct PinTitlebarButton: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Button(action: { settings.pinned.toggle() }) {
            Image(systemName: settings.pinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(settings.pinned ? .accentColor : .secondary)
                .frame(width: 32, height: 22)
        }
        .buttonStyle(.plain)
        .help(settings.pinned ? "Unpin window" : "Pin window on top")
    }
}
