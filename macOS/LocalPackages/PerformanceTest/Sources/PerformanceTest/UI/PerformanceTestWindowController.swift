import AppKit
import SwiftUI

/// Stub implementation for Performance Test Window Controller
/// Full implementation will be added in PR 2
public final class PerformanceTestWindowController: NSWindowController {

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Performance Test"
        window.center()

        self.init(window: window)

        // Placeholder view
        let placeholderView = NSHostingView(rootView: PlaceholderView())
        window.contentView = placeholderView
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Performance Test Tool")
                .font(.largeTitle)
                .padding()

            Text("Full UI implementation coming in next PR")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}