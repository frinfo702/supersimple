# Vendored: swift-markdown-engine

This is a local copy of [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine)
`0.12.0` (Apache-2.0, see `LICENSE`), vendored so the app can ship a small patch.

## Local modifications

- Removed the `MarkdownEngineTests` target (no test sources are vendored).
- Fenced code blocks use `.markdownCodeBlockBackground` instead of `.backgroundColor`,
  so AppKit doesn't double-composite the translucent fill on the glyph box / ``` fences.
- `MarkdownASTStyler.swift`: inactive `[text](url)` links reserve the hidden `[`
  marker for a site favicon (kerned to icon width) so the overlay doesn't collapse.
- `FaviconProvider` gained `didLoadNotification`; the editor restyles when a
  favicon arrives.
- `NativeTextView+CmdReturn.swift`: ⌘⌫ while the editor is first responder deletes
  the current line instead of falling through to the host's Delete Note menu.

## Upgrading

To upgrade, re-copy `Sources/`, `Package.swift`, and `LICENSE` from the upstream tag and
re-apply the local modifications above.
