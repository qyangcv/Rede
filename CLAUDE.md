Rede is a native EPUB reader for macOS and iPhone, built for Chinese text. Library and reading progress sync via iCloud.

## Platforms

- macOS 26.0+ and iOS 26.0+.

## Architecture

Dependencies point one way: Epub → Library (data & sync) → Reader engine → shared views → platform apps. A lower layer never references a higher one.

- `Epub` — EPUB 2/3 parsing and text statistics. Foundation, ZIPFoundation, Kanna only.
- `Library` — SwiftData models, import, dedup/merge, CloudKit sync. No SwiftUI, no WebKit.
- `Reader` — reading engine (WebKit, JS bridge, page turning protocol), progress, style model.
- `Settings` — app-wide settings model and its persistence.
- `Shared/**/Views` — SwiftUI content views used by both platforms.
- `macOS/`, `iOS/` — app entry, windows/screens, navigation, toolbars, gestures, lifecycle, and every platform-specific implementation.

## Rules
- Do Not execute git commands.
- Do Not comment for swift code.
- Don't create or modify any file unless I explicitly ask and name the file. I make all changes myself; your job is to answer and advise. Anchor proposed edits with `file:line`.
- Complex designs are fine when they are necessary, general, and extensible. Don't patch symptoms, add defensive fallbacks.
- Platform differences are injected at composition points (app entry, `makeTurner`, view parameters), not branched inside shared code. Shared types expose callbacks and protocols; platforms supply implementations. `Shared/` never imports AppKit/UIKit except for a type alias.
- `#if os(...)` in `Shared/` only picks per-platform values of one shared concept (layout metrics, font sizes).
- Place code by who uses it today; move it to `Shared/` when the second platform needs it.
- Shared state is per book/session, not app-global, so each platform can choose its own windowing. Each platform follows its own conventions; never adapt one platform's container for the other.
- Create services and the model container at the app entry and inject them through the environment; avoid new singletons.
- Synced (CloudKit private DB): SwiftData `@Model` types and the Codable values stored in them. CloudKit rules: defaults or optionals on every property, no unique constraints, optional relationships. Synced fields must be device-independent (no layout-dependent values). Book identity is the full content hash.
- The CloudKit Production schema only grows: never rename, retype, or remove a deployed field.
- Local only: `settings.json`, downloaded fonts. Platform-conditional enum cases are allowed only here.
- Debug: bundle id `dev.qyang.Rede.debug`, data in `Application Support/Rede-Debug`, CloudKit Development. Release: CloudKit Production.
- Each chapter loads into an iframe in `reader.html`. ReadiumCSS handles pagination and typography; `reader.js` handles navigation, anchors, progress, adjacent-page peeking, and gesture recognition (it reports; platforms decide).
- The entire Swift↔JS protocol lives in `JSBridge.swift` and the `reader` object in `reader.js`: typed Swift methods calling `window.reader.*`, user scripts, and typed messages from JS. Any change lands on both sides.
- `Web/readium/` is vendored ReadiumCSS — never edit it. Override in `reader.css` or ReadiumCSS variables.