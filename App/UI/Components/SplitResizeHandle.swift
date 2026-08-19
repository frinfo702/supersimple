import AppKit
import SwiftUI

/// Drag handle that resizes a split without moving the window.
/// (`isMovableByWindowBackground` treats SwiftUI `DragGesture` as a window drag.)
struct SplitResizeHandle: NSViewRepresentable {
    enum Axis {
        /// Dragging right grows `value` (sidebar width).
        case leadingWidth
        /// Dragging up grows `value` (panel height).
        case topHeight
    }

    @Binding var value: CGFloat
    var hairline: Color
    var axis: Axis

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, axis: axis)
    }

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.axis = axis
        view.coordinator = context.coordinator
        view.hairlineColor = NSColor(hairline)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HandleView, context: Context) -> CGSize {
        switch axis {
        case .leadingWidth:
            CGSize(width: 6, height: proposal.height ?? nsView.bounds.height)
        case .topHeight:
            CGSize(width: proposal.width ?? nsView.bounds.width, height: 6)
        }
    }

    final class Coordinator {
        var value: Binding<CGFloat>
        var axis: Axis

        init(value: Binding<CGFloat>, axis: Axis) {
            self.value = value
            self.axis = axis
        }
    }

    final class HandleView: NSView {
        var coordinator: Coordinator?
        var hairlineColor: NSColor = .separatorColor {
            didSet { needsDisplay = true }
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            hairlineColor.setFill()
            let line = AppTheme.Metric.hairlineWidth
            switch coordinator?.axis {
            case .leadingWidth:
                let x = ((bounds.width - line) / 2).rounded(.down)
                NSRect(x: x, y: bounds.minY, width: line, height: bounds.height).fill()
            case .topHeight, .none:
                let y = ((bounds.height - line) / 2).rounded(.down)
                NSRect(x: bounds.minX, y: y, width: bounds.width, height: line).fill()
            }
        }

        override func resetCursorRects() {
            switch coordinator?.axis {
            case .leadingWidth:
                addCursorRect(bounds, cursor: .resizeLeftRight)
            case .topHeight, .none:
                addCursorRect(bounds, cursor: .resizeUpDown)
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let window, let coordinator else { return }
            let start = event.locationInWindow
            let startValue = coordinator.value.wrappedValue

            while true {
                guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                    break
                }
                if next.type == .leftMouseUp { break }
                switch coordinator.axis {
                case .leadingWidth:
                    coordinator.value.wrappedValue = startValue + (next.locationInWindow.x - start.x)
                case .topHeight:
                    // Window coords grow upward. Dragging the top handle up enlarges the panel.
                    coordinator.value.wrappedValue = startValue + (next.locationInWindow.y - start.y)
                }
            }
        }
    }
}
