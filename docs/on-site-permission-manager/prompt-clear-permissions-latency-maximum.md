# Prompt: declare a schema maximum for `clear_permissions_latency_ms` (privacy-triage follow-up)

Work on branch **`bartosz/on-site-permissions-1`** of the apple-browsers repo (check it out first). Never touch `docs/` on that branch; the project log lives on `bartosz/on-site-permissions`. Commit with the repo's Claude co-author trailer. **Never push.** Use XcodeBuildMCP for tests; no manual simulator testing.

## Context

PR 1 added the `clear_permissions` action to the **iOS data-clearing wide event** — the single Fire-flow event that reports per-action timing, status, and error. The branch added three fields to the wide-event source definition `iOS/PixelDefinitions/wide_events/definitions/data-clearing.json5` (`clear_permissions_status`, `clear_permissions_latency_ms`, `clear_permissions_error`), bumped the source `meta.version` 1.0 → 1.1, and committed the regenerated schema artifact `iOS/PixelDefinitions/wide_events/generated_schemas/ios-data-clearing-1.1.1.json`.

Privacy triage approved with one non-blocking note: **declare a maximum for `clear_permissions_latency_ms`.** Today the field only says "capped at 10000ms" in its description text; nothing machine-readable enforces it. The runtime already caps the value: `DataClearingWideEventData.processedDuration` (in `SharedPackages/BrowserServicesKit/Sources/BrowserServicesKit/DataClearing/DataClearingWideEventData.swift`) rounds every per-action latency to 10 ms and clamps it to [0, 10000]. This task makes the schema declare what the code already does. It is a schema change, not a behavior change.

## Steps

1. **Declare the bound.** In `iOS/PixelDefinitions/wide_events/definitions/data-clearing.json5`, on `clear_permissions_latency_ms`, add `"minimum": 0` and `"maximum": 10000`. Keep `"type": "integer"` and the description. Do **not** add `multipleOf` — the wide-event consistency tooling does not recognize it. Do not change sibling `*_latency_ms` fields or anything under `macOS/` (out of scope; note it as a follow-up in your report).
2. **Regenerate and validate.** From `iOS/`: run `npm ci` if `node_modules` is missing, then `npm run validate-pixel-defs` (this regenerates `wide_events/generated_schemas/` and runs the formatter check; if formatting fails, run `npm run pixel-lint.fix` and re-run), then `npm run check-wide-events`.
   - Expect `ios-data-clearing-1.1.1.json` to change **in place**. That is allowed: the immutability check compares against `origin/main`, and this file does not exist on main — it is new on this branch. If the check still objects, bump the source `meta.version` to `1.2` so a new artifact is generated, commit the new file, and remove the now-orphaned `1.1.1` only if the tooling tells you to.
3. **Mirror to the pixel side only if required.** The wide-event source is paired with a pixel definition, `iOS/PixelDefinitions/pixels/definitions/data_clearing_wide_event.json5`, whose per-action latency parameter is a single `keyPattern` covering all 21 actions' `_latency_ms` keys. If `check-wide-events` reports an incompatible constraint between the source field and that pixel parameter, add the same `"minimum": 0, "maximum": 10000` to the pixel parameter (it describes the runtime cap that already applies to every action) and re-run. If the check passes without it, leave the pixel definition alone.
4. **Test.** In `SharedPackages/BrowserServicesKit/Tests/BrowserServicesKitTests/DataClearing/DataClearingWideEventDataTests.swift`, next to `testJSONParameters_clearPermissionsIncludesSchemaKeys`, add one test: a 15-second `clearPermissionsDuration` must report exactly `10000` for `feature.data.ext.clear_permissions_latency_ms`, and a 4 ms interval must report `0` (rounding, non-negative). This proves the declared bounds match the runtime. Run that test class via XcodeBuildMCP.
5. **Commit and log.** Commit on `bartosz/on-site-permissions-1` — suggested message: `Declare schema bounds for clear_permissions_latency_ms`. Do not push. Add a one-line entry to the project log on the docs branch. Report back: the diff summary, the exact validation output, and whether step 3 was needed.

## Yield rules

None should trigger — no UI, no Xcode project edits. If `npm ci` needs network access you do not have, or the validator needs a tool you cannot install, stop and ask the user rather than working around it.
