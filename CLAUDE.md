Rede: native EPUB reader for macOS 26+ and iOS 26+, built for Chinese text. Library and progress sync via iCloud.

## Rules
- Never modify files unless I name the file. Advise only; anchor edits with `file:line`.
- Only read-only git commands.
- Never comment for swift code.
- Complex designs are fine when they are necessary, general, and extensible. 
- Don't patch symptoms or add defensive fallbacks.
- Each platform follows its own conventions; never adapt one platform's container for the other.
- Place code by who uses it today; move it to Shared/ when the second platform needs it.

## CloudKit
Models under `Rede/Shared` sync to CloudKit; the release scripts generate and deploy the schema.
- Register every new `@Model` in `LibrarySchema.models`.
- Production schema is additive-only: never rename or remove a stored property or model.
- Every property needs a default or is optional; relationships are optional; no `@Attribute(.unique)`.