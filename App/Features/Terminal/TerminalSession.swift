import Combine
import Foundation
import GhosttyTerminal

/// Owns the libghostty `TerminalView` so a login shell can outlive SwiftUI
/// hierarchy diffs (sidebar show/hide) and panel hide/show.
///
/// Spawning is deferred until the first ⌘J so launch does not pay for Ghostty
/// init. The surface uses the exec (PTY) backend with no command override, which
/// starts the user's macOS login shell (`$SHELL` / passwd shell) in the home
/// directory. Ghostty's own config files and shell-integration scripts are not
/// loaded.
@MainActor
final class TerminalSession: ObservableObject {
    private(set) var context: TerminalViewState?
    /// Held here, not by SwiftUI, so `NSViewRepresentable` identity changes
    /// reparent this view instead of tearing down the PTY.
    private(set) var terminalView: TerminalView?
    private var isRestarting = false

    func prepare() {
        guard context == nil else { return }
        let state = makeContext()
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 220))
        view.delegate = state
        view.controller = state.controller
        view.configuration = state.configuration
        context = state
        terminalView = view
        objectWillChange.send()
    }

    func restart() {
        guard !isRestarting else { return }
        isRestarting = true
        defer { isRestarting = false }

        context?.onClose = nil
        if terminalView == nil {
            context = nil
            prepare()
            return
        }
        let state = makeContext()
        context = state
        terminalView?.delegate = state
        terminalView?.controller = state.controller
        terminalView?.configuration = state.configuration
        objectWillChange.send()
    }

    /// Re-sync Ghostty's Metal surface after the host view moves (sidebar toggle).
    func refreshLayout() {
        guard let view = terminalView, view.bounds.width > 0, view.bounds.height > 0 else {
            return
        }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.fitToSize()
        view.displayIfNeeded()
    }

    private func makeContext() -> TerminalViewState {
        let controller = TerminalController { builder in
            builder.withCustom("shell-integration", "none")
        }
        let state = TerminalViewState(controller: controller)
        state.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        state.onClose = { [weak self] _ in
            guard let self, !self.isRestarting else { return }
            // View teardown detaches the NSView; only respawn if the surface is
            // still on-screen (the user typed `exit`, not a SwiftUI rebuild).
            guard self.terminalView?.window != nil else { return }
            self.restart()
        }
        return state
    }
}
