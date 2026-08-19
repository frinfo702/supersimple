import Combine
import Foundation
import GhosttyTerminal

/// Owns the libghostty surface so a login shell can outlive hide/show.
///
/// Spawning is deferred until the first ⌘J so launch does not pay for Ghostty
/// init. The surface uses the exec (PTY) backend with no command override, which
/// starts the user's macOS login shell (`$SHELL` / passwd shell) in the home
/// directory. Ghostty's own config files and shell-integration scripts are not
/// loaded.
@MainActor
final class TerminalSession: ObservableObject {
    private(set) var context: TerminalViewState?

    func prepare() {
        guard context == nil else { return }
        context = makeContext()
        objectWillChange.send()
    }

    func restart() {
        context?.onClose = nil
        context = makeContext()
        objectWillChange.send()
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
            self?.restart()
        }
        return state
    }
}
