Rede is a native EPUB reader for macOS and iOS, built for Chinese text, sync through iCloud.

## Platforms

macOS 26.0+ and iOS 26.0+.

## Layout

- `Rede/Shared/` — code used by both platforms:
  - `Common/` — small cross-cutting helpers
  - `Epub/` — EPUB 2/3 parsing, no UI dependencies
  - `Library/` — book library, import, iCloud sync; `Views/` holds shared library views
  - `Reader/` — reading session, progress, styling, page turning; `Views/` holds shared reader views
  - `Settings/` — settings panes
- `Rede/macOS/`, `Rede/iOS/` — app entry and top-level UI: windows/screens, navigation, toolbars, and how things are presented. Also anything that imports AppKit/UIKit for more than a type alias.
- Place code by who uses it today: both platforms → `Shared/`; one platform → that platform's folder. When the other platform needs it, move it to `Shared/` then. Don't put single-platform code in `Shared/` behind `#if os(...)`.
- Anything that defines synced or persisted data (models, progress, settings formats) lives in `Shared/`, since both platforms must read and write it identically.
- Design each platform's UI to its own conventions. Never adapt a macOS container for iOS or vice versa; reuse only the shared content views inside it.
- `Rede/Shared/Reader/Web/` — the rendering layer. Each chapter loads into an iframe inside `reader.html`; ReadiumCSS handles pagination and typography, and `reader.js` only handles navigation, anchors, and progress.
- Swift talks to JS exclusively through `JSBridge.swift`, which calls `window.reader.*`. Any change to that interface must land on both sides.
- `Web/readium/` is vendored ReadiumCSS — never edit it. Override in `reader.css` or through ReadiumCSS variables instead.

## Working with me

- Always reply in the language I write in.
- Don't create or modify any file unless I explicitly ask and name the file. I make all changes myself; your job is to answer and advise.
- Rede is in early, fast iteration with almost no users. Don't write migrations or keep backward compatibility for old data, settings, or APIs — change formats and schemas freely. If a change will break existing local data, just tell me so I can reset it.
- Complex designs are fine when they are necessary, general, and extensible. Don't patch symptoms, add defensive fallbacks, or pile on special cases — I prefer the simplest implementation that actually works.
