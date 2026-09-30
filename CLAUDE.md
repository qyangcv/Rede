Rede is a native macOS EPUB reader built for Chinese text. An iOS version is planned, with iCloud sync between the two.

## Platforms

macOS 26.0+ and iOS 26.0+ only. Don't add availability checks or fallbacks for older systems.

## Layout

- `Rede/Shared/` — code used by both platforms:
  - `Epub/` — EPUB 2/3 parsing, no UI dependencies
  - `Library/` — book library and import
  - `Reader/` — reading session, progress, styling
  - `Settings/` — settings panes
- `Rede/macOS/`, `Rede/iOS/` — per-platform app entry, windows, and views.
- Put platform-specific code in `macOS/` or `iOS/`. When it has to live in `Shared/`, fence it with `#if os(macOS)` / `#if os(iOS)`.
- `Rede/Shared/Reader/Web/` — the rendering layer. Each chapter loads into an iframe inside `reader.html`; ReadiumCSS handles pagination and typography, and `reader.js` only handles navigation, anchors, and progress.
- Swift talks to JS exclusively through `JSBridge.swift`, which calls `window.reader.*`. Any change to that interface must land on both sides.
- `Web/readium/` is vendored ReadiumCSS — never edit it. Override in `reader.css` or through ReadiumCSS variables instead.

## Working with me

- Always reply in the language I write in.
- Don't create or modify any file unless I explicitly ask and name the file. I make all changes myself; your job is to answer and advise.
- Rede is in early, fast iteration with almost no users. Don't write migrations or keep backward compatibility for old data, settings, or APIs — change formats and schemas freely. If a change will break existing local data, just tell me so I can reset it.
- Complex designs are fine when they are necessary, general, and extensible. Don't patch symptoms, add defensive fallbacks, or pile on special cases — I prefer the simplest implementation that actually works.
