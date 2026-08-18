import AppKit
import SwiftUI

/// Makes the title bar transparent and full-size so a SwiftUI toolbar sits on
/// the same row as the traffic-light buttons instead of dropping below them.
/// `title` is the Mission Control / window-cycle name; the titlebar itself stays hidden.
struct WindowChrome: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView {
        Accessor()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Accessor)?.title = title
        (nsView as? Accessor)?.apply()
    }

    private final class Accessor: NSView {
        var title: String = "supersimple"

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            DispatchQueue.main.async { [weak self] in
                self?.stripToolbarItemChrome()
            }
        }

        func apply() {
            guard let window else { return }
            window.title = title
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.toolbarStyle = .unified
            window.animations["appearance"] = NSNull()
            stripToolbarItemChrome()
        }

        func stripToolbarItemChrome() {
            for item in window?.toolbar?.items ?? [] {
                item.isBordered = false
            }
        }
    }
}
