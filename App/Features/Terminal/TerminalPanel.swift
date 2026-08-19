import AppKit
import GhosttyTerminal
import SwiftUI

/// Bottom-docked libghostty surface under the editor. Chrome is a hairline drag
/// handle; the emulator itself is an unmodified system login shell.
struct TerminalPanel: View {
    @ObservedObject var session: TerminalSession
    @Binding var height: CGFloat
    var visible: Bool
    var focusToken: UInt
    var palette: PaletteColors

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            SplitResizeHandle(value: $height, hairline: palette.hairline, axis: .topHeight)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .contentShape(Rectangle())
                .accessibilityIdentifier("terminal-resize-handle")
                .accessibilityLabel("Resize terminal")
                .accessibilityAddTraits(.isButton)
            HostedTerminalSurface(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("terminal-surface")
                .accessibilityLabel("Terminal")
        }
        .background(palette.editor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-panel")
        .onAppear {
            syncAppearance()
            focusTerminalIfNeeded()
        }
        .onChange(of: colorScheme) { _, _ in
            syncAppearance()
        }
        .onChange(of: palette) { _, _ in
            syncAppearance()
        }
        .onChange(of: focusToken) { _, _ in
            focusTerminalIfNeeded()
        }
    }

    private func syncAppearance() {
        session.applyAppearance(
            ColorTheme.named(palette.themeID).terminalTheme(),
            colorScheme: colorScheme
        )
    }

    private func focusTerminalIfNeeded() {
        guard visible, let view = session.terminalView else { return }
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }
}

/// Embeds `TerminalSession.terminalView` without taking ownership, so SwiftUI
/// can rebuild the representable (sidebar toggle) without killing the PTY.
private struct HostedTerminalSurface: NSViewRepresentable {
    var session: TerminalSession

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.attach(session.terminalView)
        return host
    }

    func updateNSView(_ host: TerminalHostView, context: Context) {
        host.attach(session.terminalView)
    }

    static func dismantleNSView(_ host: TerminalHostView, coordinator: ()) {
        host.detachIfAttached()
    }
}

private final class TerminalHostView: NSView {
    private(set) weak var terminal: TerminalView?

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        terminal?.frame = bounds
        if bounds.width > 0, bounds.height > 0 {
            terminal?.fitToSize()
        }
    }

    func attach(_ view: TerminalView?) {
        guard let view else { return }
        if view.superview !== self {
            view.removeFromSuperview()
            addSubview(view)
        }
        terminal = view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
    }

    func detachIfAttached() {
        guard let terminal, terminal.superview === self else { return }
        terminal.removeFromSuperview()
        self.terminal = nil
    }
}
