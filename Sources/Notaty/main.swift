import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
// withExtendedLifetime keeps a strong reference to delegate for the entire
// duration of app.run(). NSApplication.delegate is weak, so without this the
// ARC optimizer may release `delegate` immediately, crashing on first callback.
withExtendedLifetime(delegate) {
    app.run()
}
