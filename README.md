# supersimple

A minimalist, super-lightweight macOS notes app with an Obsidian-style **live Markdown
preview**, native LaTeX rendering, and full-text search. Inspired by the clean, restrained
aesthetic of Superlogical — no clutter, no redundant toolbars.

Built entirely with native Apple frameworks (SwiftUI + AppKit/TextKit 2). No Electron,
no `WKWebView`, no JavaScript runtime.

![macOS](https://img.shields.io/badge/macOS-14%2B-lightgrey)

## Features

- **Live preview** — Markdown is edited and rendered in the same surface; the syntax
  markers reveal themselves where the caret is. Headings, bold/italic, links, blockquotes,
  lists, task lists, tables, strikethrough, and horizontal rules are all native.
- **LaTeX** — inline `$...$` and display `$$...$$` math is typeset natively with
  [SwiftMath](https://github.com/mgriebling/SwiftMath) and rendered in-place.
- **Code blocks** — fenced blocks use bundled **Geist Mono**, with language display and a
  lightweight native (regex-based) syntax highlighter — no heavy JS or theme bundles.
- **Full-text search** — SQLite FTS5 (BM25-ranked) over title, body, and tags, with
  snippets. The index is a derived cache that rebuilds from your `.md` files.
- **Tags, no folders** — tags are YAML frontmatter, auto-picked-up from `#tags` in the body.
  No hierarchy, just flat filterable notes.
- **Plain Markdown files** — each note is a `.md` file in
  `~/Library/Application Support/Supersimple/Notes/`. Atomic writes, autosave debounce,
  sync flush on quit.
- **Minimal design** — hidden navbar title, standard traffic lights, subtle warm accent,
  near-black theme, and dark/light/system appearance.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 26 (for building from source)
- Homebrew + [xcodegen](https://github.com/yonaskolb/XcodeGen) (to generate the project)

## Architecture

```
App/                       macOS app
  App/                     entry point, AppModel (single @Observable state holder)
  Features/                Library (sidebar), Editor (live preview), etc.
  Resources/               Info.plist, entitlements, Geist Mono font, asset catalog
  UI/Theme/                design tokens (near-black palette, accent)
Packages/SupersimpleCore/  platform-neutral library (maintainable, testable in isolation)
  Sources/Models/          Note, Tag
  Sources/Persistence/     FrontmatterCodec, NoteFileManager (atomic I/O)
  Sources/Search/          NoteSearchIndex (FTS5)
  Sources/Markdown/        MarkdownScanner (math/code-fence detection, pure)
supersimpleTests/          AppModel end-to-end tests
supersimpleUITests/        UI smoke tests
Scripts/                   build.sh, format.sh, generate_icon.swift
```

- `AppModel` is the single `@MainActor @Observable` owner of application state: the in-memory
  notes, the current edit buffer, the search index, and debounced persistence.
- File I/O and the FTS index live in `SupersimpleCore`, which has **zero** Apple-framework
  dependencies beyond Foundation, so unit tests run headless and fast.
- The editor is [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine)
  `0.12.0` (pinned via `project.yml` + `Package.resolved`). Its pre-1.0 API is isolated behind
  `EditorView`.
- Markdown files are the source of truth; the SQLite DB is rebuildable on demand.

## Building

```sh
brew install xcodegen      # once
xcodegen generate          # regenerate supersimple.xcodeproj
open supersimple.xcodeproj # build & run in Xcode
```

Or build + sign for local use:

```sh
./Scripts/build.sh          # Debug, ad-hoc signed, copied to dist/supersimple.app
./Scripts/build.sh release  # Release build
```

### Why local signing?

Gatekeeper quarantines apps downloaded from the internet. Because the app is built on your
own machine here it carries no quarantine attribute, so no notarization is required. To also
be signed with a hardened runtime, `Scripts/build.sh` ad-hoc signs the bundle. (A Developer ID
would be needed to distribute a non-quarantined copy to others; out of scope here.)

## Testing

```sh
# Core package unit + performance tests
cd Packages/SupersimpleCore
RUN_PERF_TESTS=1 swift test

# macOS app unit tests
xcodebuild test -scheme supersimple -destination 'platform=macOS'
```

`Scripts/format.sh` and `Scripts/format.sh lint` run `swift-format` (Xcode-bundled) over all
sources. CI runs format lint, the Core tests, the unit tests, and a Release build, uploading
the `.xcresult` and the built `.app` as artifacts.

## Keyboard

- `⌘N` new note
- `⌘S` save now
- `⌥⌘S` toggle sidebar

## Dependencies

| Package | Purpose | License |
| --- | --- | --- |
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) 0.12.0 | TextKit 2 live-preview editor | Apache-2.0 |
| [SwiftMath](https://github.com/mgriebling/SwiftMath) | Native LaTeX typesetting | 2-Clause BSD |
| [Geist Mono](https://vercel.com/font) | Code-block monospace font | SIL OFL 1.1 |