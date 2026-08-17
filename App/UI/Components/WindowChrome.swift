import AppKit
import SwiftUI

/// Makes the title bar transparent and full-size so a SwiftUI toolbar sits on
/// the same row as the traffic-light buttons instead of dropping below them.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Accessor()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Accessor)?.apply()
    }

    private final class Accessor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.toolbarStyle = .unified
            window.animations["appearance"] = NSNull()
        }
    }
}
