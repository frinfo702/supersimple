import AppKit
import GhosttyTerminal
import SwiftUI

/// Bottom-docked libghostty surface under the editor. Chrome is a hairline drag
/// handle; the emulator itself is an unmodified system login shell.
struct TerminalPanel: View {
    @ObservedObject var context: TerminalViewState
    @Binding var height: CGFloat
    var visible: Bool
    var focusToken: UInt
    var palette: PaletteColors

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TerminalResizeHandle(height: $height, hairline: palette.hairline)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .accessibilityIdentifier("terminal-resize-handle")
                .accessibilityLabel("Resize terminal")
                .accessibilityAddTraits(.isButton)
            TerminalSurfaceView(context: context)
                .terminalFocused($focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("terminal-surface")
                .accessibilityLabel("Terminal")
        }
        .background(palette.editor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-panel")
        .onAppear {
            if visible { focused = true }
        }
        .onChange(of: focusToken) { _, _ in
            if visible { focused = true }
        }
    }
}

/// AppKit handle so a drag resizes the panel instead of moving the window.
/// (`isMovableByWindowBackground` treats SwiftUI `DragGesture` as a window drag.)
private struct TerminalResizeHandle: NSViewRepresentable {
    @Binding var height: CGFloat
    var hairline: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        context.coordinator.height = $height
        view.coordinator = context.coordinator
        view.hairlineColor = NSColor(hairline)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HandleView, context: Context) -> CGSize {
        CGSize(width: proposal.width ?? nsView.bounds.width, height: 6)
    }

    final class Coordinator {
        var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) {
            self.height = height
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

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: 6)
        }

        override func draw(_ dirtyRect: NSRect) {
            hairlineColor.setFill()
            let lineHeight = AppTheme.Metric.hairlineWidth
            let y = ((bounds.height - lineHeight) / 2).rounded(.down)
            NSRect(x: bounds.minX, y: y, width: bounds.width, height: lineHeight).fill()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let startY = event.locationInWindow.y
            let startHeight = coordinator?.height.wrappedValue ?? AppTheme.Metric.terminalHeight

            while true {
                guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                    break
                }
                if next.type == .leftMouseUp { break }
                // Window coords grow upward. Dragging the top handle up enlarges the panel.
                coordinator?.height.wrappedValue = startHeight + (next.locationInWindow.y - startY)
            }
        }
    }
}
