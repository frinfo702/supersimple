import AppKit
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
    private let toggleMonitor = ToggleShortcutMonitor()

    func prepare() {
        guard context == nil else { return }
        let state = makeContext()
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 220))
        view.delegate = state
        view.controller = state.controller
        view.configuration = state.configuration
        context = state
        terminalView = view
        toggleMonitor.view = view
        objectWillChange.send()
    }

    /// Ghostty swallows ⌘J while it is first responder. Intercept that chord
    /// before `performKeyEquivalent` and hide the panel without killing the PTY.
    func installToggleShortcut(_ handler: @escaping @MainActor () -> Void) {
        toggleMonitor.view = terminalView
        toggleMonitor.onToggle = handler
        toggleMonitor.install()
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
        // A fresh controller defaults to `.light`; carry the active scheme over
        // so `exit` in dark mode does not restart the shell in light mode.
        let scheme = context?.effectiveColorScheme
        let state = makeContext()
        if let scheme {
            state.adopt(terminalColorScheme: scheme)
        }
        context = state
        terminalView?.delegate = state
        terminalView?.controller = state.controller
        terminalView?.configuration = state.configuration
        syncFocus()
        objectWillChange.send()
    }

    /// The replacement Ghostty surface is created focused by default. Re-sync it
    /// with the actual AppKit first responder so cursor/focus state matches the
    /// real input target after a restart.
    private func syncFocus() {
        guard let view = terminalView, let window = view.window else { return }
        if window.firstResponder === view {
            // Already focused; the new surface defaults focused, so nothing to do.
            return
        }
        // Terminal is not the first responder but the new surface reports
        // focused. Cycle focus through the view to push the unfocused state
        // down, then restore the previous first responder.
        let previous = window.firstResponder
        window.makeFirstResponder(view)
        window.makeFirstResponder(previous)
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
            // Host shortcut: hide the panel. Ghostty would otherwise consume ⌘J.
            builder.withCustom("keybind", "super+j=unbind")
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

/// Local key monitor so ⌘J reaches the host while Ghostty is first responder.
/// Not `@MainActor`: `NSEvent` monitors are not isolated, and `NSEvent` is not Sendable.
private final class ToggleShortcutMonitor: @unchecked Sendable {
    weak var view: NSView?
    var onToggle: (@MainActor () -> Void)?
    private var token: Any?

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.intercept(event)
        }
    }

    private func intercept(_ event: NSEvent) -> NSEvent? {
        guard Self.isCommandJ(event) else { return event }
        guard let view, Self.terminalIsFirstResponder(view, in: event.window) else {
            return event
        }
        Task { @MainActor in
            self.onToggle?()
        }
        return nil
    }

    private static func terminalIsFirstResponder(_ view: NSView, in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder === view { return true }
        if let focused = responder as? NSView {
            return focused === view || focused.isDescendant(of: view)
        }
        return false
    }

    /// kVK_ANSI_J. Command only — Shift/Option/Control must not match.
    private static func isCommandJ(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chord: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        guard mods.intersection(chord) == .command else { return false }
        return event.keyCode == 38 || event.charactersIgnoringModifiers?.lowercased() == "j"
    }
}
