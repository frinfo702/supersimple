# Vendored: swift-markdown-engine

This is a local copy of [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine)
`0.12.0` (Apache-2.0, see `LICENSE`), vendored so the app can ship a small patch.

## Local modifications

- Local `MarkdownEngineTests` cover Tab indent, `LinePrefixGlue`, overlay
  glyph baseline, and nested ordered-list outline markers (upstream tests
  were not vendored).
- Fenced code blocks use `.markdownCodeBlockBackground` instead of `.backgroundColor`,
  so AppKit doesn't double-composite the translucent fill on the glyph box / ``` fences.
- `MarkdownASTStyler.swift`: inactive `[text](url)` links reserve the hidden `[`
  marker for a site favicon (kerned to icon width) so the overlay doesn't collapse.
- `FaviconProvider` gained `didLoadNotification`; the editor restyles when a
  favicon arrives.
- `NativeTextView+CmdReturn.swift`: ⌘⌫ while the editor is first responder deletes
  the current line instead of falling through to the host's Delete Note menu.
- `NativeTextView+CaretWorkarounds.swift`: crop the TextKit 2 insertion indicator
  to the run's em-box and pin it to the line's typographic bottom — extra
  `minimumLineHeight` leading sits above the glyphs. Do not copy segment-frame
  origin (container space) onto the indicator (view space).
- `LinePrefixGlue.swift`: presentation-only WORD JOINER substitution for the
  trailing space after a list/blockquote marker so a long unbreakable run wraps
  on the first line instead of dropping below the marker. Leading indent tabs
  are left intact so Tab indent keeps its tab-stop width. Hidden bullets collapse
  `- ` into the paragraph indent so wrapped lines and the caret share the same origin.
  Collapsed bullets pin the painted `•` to the line's body em-box so a newly
  continued empty `- ` item does not draw the dot on the 0.1pt marker baseline.
- Nested ordered lists overlay outline markers by indent: `1, 2, …` → `a, b, …`
  → `i, ii, iii, …` → `1, 2, …`. Nested runs restart at 1 (`2.` after Tab is `a.`,
  not `b.`). Source stays Markdown digits. Backspace on an empty nested item
  outdents one level (same as ⇧⇥) so the overlay tracks depth; default Backspace
  would delete the marker's trailing space and leave a tab + raw `2.`.
- `EmbeddedImageProvider.didLoadNotification` restyles when a remote `![](url)`
  image arrives. Empty-alt images plant on `!` so the overlay has an anchor.
- Editable wiki links keep a plain click for caret placement and navigate only on
  Command-click, including the fallback path for dropped AppKit link events.

## Upgrading

To upgrade, re-copy `Sources/`, `Package.swift`, and `LICENSE` from the upstream tag and
re-apply the local modifications above.
