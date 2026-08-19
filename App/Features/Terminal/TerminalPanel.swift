import AppKit
import GhosttyTerminal
import SwiftUI

/// Bottom-docked libghostty surface. Chrome is a hairline drag handle; the
/// emulator itself is an unmodified system login shell.
struct TerminalPanel: View {
    @ObservedObject var context: TerminalViewState
    @Binding var height: CGFloat
    var visible: Bool
    var focusToken: UInt
    var palette: PaletteColors

    @FocusState private var focused: Bool
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
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

    private var resizeHandle: some View {
        ZStack {
            palette.hairline
                .frame(height: AppTheme.Metric.hairlineWidth)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartHeight == nil {
                        dragStartHeight = height
                    }
                    height = (dragStartHeight ?? height) - value.translation.height
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .accessibilityIdentifier("terminal-resize-handle")
        .accessibilityLabel("Resize terminal")
        .accessibilityAddTraits(.isButton)
    }
}
