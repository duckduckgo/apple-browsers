---
name: ddg-add-pixel
description: Use when adding, renaming or changing a pixel or wide event on iOS, macOS or in SharedPackages, including its JSON5 definition and tests.
---

# Add or change a pixel

These steps cover the usual case. For anything they don't, the Swift API reference is
`SharedPackages/PixelKit/Sources/PixelKit/README.md`, and the definition rules are in
`REVIEW-pixels.md`, which Claude Code Review also applies to the PR.

1. **Find what exists.** `git grep` the feature name in `iOS/PixelDefinitions`,
   `macOS/PixelDefinitions` and `*Pixel*.swift`. Extend the feature's existing `PixelKit.Event`
   enum when there is one; otherwise create one in its own file. `iOS/Core/PixelEvent.swift` is
   closed to new cases, and Danger fails a PR that adds one.
2. **Name it** `feature_action` or `feature-subfeature_action`: descriptive, without an `m_` or
   `m-` prefix, and without legacy shorthand like `ml`.
   - iOS: leave `ios` out of the name. PixelKit appends `_ios_phone` / `_ios_tablet`.
   - macOS: end the name with `_macos` and declare `var namePrefix: PixelKitNamePrefix { .none }`,
     otherwise PixelKit prepends `m_mac_`. See `macOS/DuckDuckGo/Statistics/FireButtonPixel.swift`.
3. **Pick the frequency:**
   - `.standard` sends every time; `.daily` once per day per device.
   - `.dailyAndCount` sends both, for anything that can spike, such as an error.
   - `.uniqueByName` sends once per install, and the name must end `_u`.
   - The `legacy…` cases exist only for pixels that already ship with their suffixes. The README's
     frequency table lists the rest.
4. **Fire through an injected `PixelFiring?`** that defaults to `PixelKit.shared`. Spell the
   concrete type, `fire(MyPixel.someCase)`; the leading-dot form `.someCase` does not compile.
   Bucket numbers, and keep PII and URLs out of names and parameters.
   - Three or more pixels for one flow, or a wide event: put them behind a
     `<Feature>Instrumentation` protocol with a default implementation, like
     `iOS/DuckDuckGo/AIChat/WideEvent/DuckAISessionInstrumentation.swift`.
   - `.withRetry` or `.withATB`: stop and ask the user for privacy triage first.
5. **Define it** in `{iOS,macOS}/PixelDefinitions/pixels/definitions/`, starting from the
   `TEMPLATE.json5` in that folder.
   - List every parameter the pixel sends: `appVersion` unless the call opts out, `errorCode` and
     `errorDomain` (plus the underlying pair) when the event carries an error, and `pixelSource`
     when the event declares it.
   - List suffixes in the order PixelKit emits them: frequency, then `platform`, then
     `form_factor` (the last two on iOS only).
   - A pixel fired from SharedPackages needs a definition on every platform that fires it.
6. **Wide events** also follow the "Wide events" section of `REVIEW-pixels.md`: both definition
   files, matching version bumps, anchored `keyPattern`s, and no edits to `generated_schemas/`.
7. **Test** with `PixelKitMock` (`@_spi(Testing) import PixelKit`), asserting on its
   `actualFireCalls`.
8. **Validate** from `iOS/` or `macOS/`: `npm ci --include-workspace-root` once, then
   `npm run validate-pixel-defs`, `npm run check-wide-events`, and `npm run pixel-lint.fix` to
   format. CI also checks `owners` against an internal GitHub user map that local runs skip, so
   use GitHub usernames.

Done when every name the Swift code can send has a definition whose parameters and suffixes match,
and the validators pass.
