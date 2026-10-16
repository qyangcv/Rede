Rede: native EPUB reader for macOS 26+ and iOS 26+, built for Chinese text. Library and progress sync via iCloud.

## Rules
- Never modify files unless I name the file. Advise only; anchor edits with `file:line`.
- Only read-only git commands.
- Never comment for swift code.
- Complex designs are fine when they are necessary, general, and extensible. 
- Don't patch symptoms or add defensive fallbacks.
- Each platform follows its own conventions; never adapt one platform's container for the other.
- Place code by who uses it today; move it to Shared/ when the second platform needs it.

## CloudKit schema
The storage model under `Rede/Shared` is mirrored to CloudKit, so every new `@Model` or stored property is a cloud schema change:
1. Run a Debug build (Development environment) through the affected flow, otherwise the record type never materializes.
2. `bash scripts/cloudkit-schema.sh record`, then commit `cloudkit/schema.ckdb`.
3. Deploy in the CloudKit Console (Schema → Deploy Schema Changes), then `bash scripts/cloudkit-schema.sh check`.

Both release scripts run `check` before archiving and abort while Production is behind. `cktool` can only write the development schema; production deploys are Console-only. Release steps are documented in `RELEASING.md`.