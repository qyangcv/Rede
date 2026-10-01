Rede is a native EPUB reader for macOS and iPhone, built for Chinese text. Library and reading progress sync via SwiftData + CloudKit.

This file describes the intended architecture. Where code disagrees with it, this file wins: point out the deviation instead of copying it.

## Platforms & toolchain

- macOS 26.0+ and iOS 26.0+ only, iPhone only. Use current APIs directly; never add `#available` checks or fallbacks.
- macOS ships as a Developer ID DMG with Sparkle, without App Sandbox; iOS ships through App Store Connect.
- Swift 6 language mode, default actor isolation `MainActor`. Mark background work `nonisolated` / `@concurrent` explicitly; values crossing isolation must be `Sendable`.
- Dependencies: ZIPFoundation, Kanna, Sparkle (macOS only). Ask before adding any.
- Build: `xcodebuild -scheme Rede -destination 'platform=macOS' build`, `xcodebuild -scheme "Rede iOS" -destination 'generic/platform=iOS Simulator' build`. Never run `scripts/release*.sh`.

## Architecture

Dependencies point one way: Epub → Library (data & sync) → Reader engine → shared views → platform apps. A lower layer never references a higher one.

- `Epub` — EPUB 2/3 parsing and text statistics. Foundation, ZIPFoundation, Kanna only.
- `Library` — SwiftData models, import, dedup/merge, CloudKit sync. No SwiftUI, no WebKit.
- `Reader` — reading engine (WebKit, JS bridge, page turning protocol), progress, style model.
- `Settings` — app-wide settings model and its persistence.
- `Shared/**/Views` — SwiftUI content views used by both platforms.
- `macOS/`, `iOS/` — app entry, windows/screens, navigation, toolbars, gestures, lifecycle, and every platform-specific implementation.

Rules:
- Models are plain values. Translating them to CSS, JS, or storage formats belongs to the boundary layer that needs it.
- Platform differences are injected at composition points (app entry, `makeTurner`, view parameters), not branched inside shared code. Shared types expose callbacks and protocols; platforms supply implementations. `Shared/` never imports AppKit/UIKit except for a type alias.
- `#if os(...)` in `Shared/` only picks per-platform values of one shared concept (layout metrics, font sizes).
- Place code by who uses it today; move it to `Shared/` when the second platform needs it.
- Shared state is per book/session, not app-global, so each platform can choose its own windowing. Each platform follows its own conventions; never adapt one platform's container for the other.
- Create services and the model container at the app entry and inject them through the environment; avoid new singletons.

## Data

- Synced (CloudKit private DB): SwiftData `@Model` types and the Codable values stored in them. CloudKit rules: defaults or optionals on every property, no unique constraints, optional relationships. Synced fields must be device-independent (no layout-dependent values). Book identity is the full content hash.
- The CloudKit Production schema only grows: never rename, retype, or remove a deployed field. Everything else (local stores, `settings.json`, the Development schema) can change freely — tell me what to reset.
- Local only: `settings.json`, downloaded fonts. Platform-conditional enum cases are allowed only here.
- Debug: bundle id `dev.qyang.Rede.debug`, data in `Application Support/Rede-Debug`, CloudKit Development. Release: CloudKit Production.

## Rendering layer (`Shared/Reader/Web/`)

- Each chapter loads into an iframe in `reader.html`. ReadiumCSS handles pagination and typography; `reader.js` handles navigation, anchors, progress, adjacent-page peeking, and gesture recognition (it reports; platforms decide).
- The entire Swift↔JS protocol lives in `JSBridge.swift` and the `reader` object in `reader.js`: typed Swift methods calling `window.reader.*`, user scripts, and typed messages from JS. Any change lands on both sides.
- Text offsets (`ReadingPosition.offset`, chapter lengths) are UTF-16 code units, matching JS string indices.
- `Web/readium/` is vendored ReadiumCSS — never edit it. Override in `reader.css` or ReadiumCSS variables.

## Conventions

- Pure logic (parsing, merging, position math) gets Swift Testing tests.
- Comments in Chinese, explaining why. UI strings in Chinese. Logger subsystem is the bundle id.

## Working with me

- Always reply in the language I write in.
- Don't create or modify any file unless I explicitly ask and name the file. I make all changes myself; your job is to answer and advise. Read-only commands and builds are fine; anchor proposed edits with `file:line`.
- No migrations or backward compatibility, except the CloudKit Production rule above.
- Complex designs are fine when they are necessary, general, and extensible. Don't patch symptoms, add defensive fallbacks, or pile on special cases — I prefer the simplest implementation that actually works.