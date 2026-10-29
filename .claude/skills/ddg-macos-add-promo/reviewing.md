# Reviewing a promo implementation

For reviewing a PR or diff, and for your own self-review before finishing. For each finding, cite the file and line and say what happens at runtime — "this looks off" isn't a finding. Field semantics are in [reference.md](reference.md); read the diff's factory file, delegate, and the current `makeAllPromos` before starting.

## Check these first — they compile and fail silently

1. **Delegate protocol vs. `Promo` subtype.** Initializers enforce the match, but `setDelegate(for:delegate:)` takes `any PromoDelegate`. A mismatch wired that way compiles, and `PromoService` either skips the promo forever or, if it conforms to the other protocol, runs it under that type's rules. An `InternalPromo` with only an `ExternalPromoDelegate` bypasses its triggers and `checkRules` entirely.
2. **Resolution paths vs. one-shot or recurring.** Trace every exit of `show()` and the timeout result. `.actioned`, bare `.ignored()`, or `.retired` on any path of a recurring promo retires it for the life of the profile. The CTA path is the one most often wrong, and it silences the most engaged users.
3. **Coexistence.** Every claimed coexistence needs *both* promos to list each other in `coexistingPromoIDs`; one-sided is inert. `.global` conflicts with every context unless mutually listed.
4. **Timeouts.** `nil` overrides inherit the base type's timeout. A PR claiming "stays until dismissed" is only right if the base type's own `timeoutInterval` is `nil`. A short `customTimeoutResult` cooldown on a medium+ promo is floored by the global cooldown unless `setsGlobalCooldown: false`. A promo on screen when the app quits is restored at next launch, bypassing `checkRules` and permanent dismissal, unless its timeout ran out while the app was closed. Early resolutions that shouldn't survive a restart must clear `lastShown` (`.noChange` and `.retired` do).

## Fields

5. **`promoType` severity matches the interruption the UI causes** (and the PR's own description of it) — check the table, not the type's name. Low severity chosen to dodge a collision is a finding.
6. **`context` is where it renders.** Chrome (tab bar, address bar, toolbar) is `.global`. A new `PromoContext` case for chrome, or one added to escape `.global`, silently stops the promo yielding.
7. **`triggers` are the described event**, not an approximation. A single one-shot trigger on a medium+ promo is easily lost for good. A condition that can hold at launch needs `.appLaunched` too.
8. **`initiated` is what caused it to appear**, not what gives a convenient cooldown.
9. **Priority position is justified in the PR**, relative to its neighbours. An unexplained append to the end is a finding. Read the whole `makeAllPromos`, since promos are also `insert`ed after the literal.
10. **Exceptions** (`respectsGlobalCooldown: false`, `setsGlobalCooldown: false`, coexistence) have product sign-off referenced in the PR.
11. **Consistency**: two promos in one diff making opposite calls on the same question.

## Delegate

12. The class isn't `@MainActor` — only `show` and `hide` are.
13. `hide()` is idempotent and resumes a pending continuation; presentation failure resolves `.noChange`.
14. `isEligible` reflects current state only, not a home-made "shown before" record; the publisher replays and de-duplicates.
15. Eligibility turning `true` is expected to show the promo? It won't without a trigger.
16. The delegate and UI live with the feature, not under `Promotions/`.
17. The factory doesn't return `Promo?` or conditionally omit the promo; the kill switch is gated in the delegate, not the factory.

## Migrations

18. The legacy presentation path is **gone**, not kept behind the kill switch being off; the old timer is removed, with `autoDismissDuration: nil`.
19. There's a `promoQueue<Name>Promo` kill switch.
20. `show()` returns `.retired` when the legacy flag is set, and `force` bypasses it. The flag is read through injected `KeyedStorage`, not `@UserDefaultsWrapper`, with its raw string unchanged.
21. Each legacy value (cap, timeout, pixels, hover) is preserved, or its change is signed off.
22. No dead presenter code, unread `lastShown`-style state, stale method names, or stale doc comments remain.

## Code quality

23. **Comments** explain why, not what, using `//` and `///`. A doc comment restating the signature, or describing frequency and severity the fields already declare, is a finding.
24. **Rationalizing comments**: any comment or PR sentence justifying a field by the rule it avoids ("chosen because X would suppress it") is either an unflagged rule break or a wrong field elsewhere. It isn't acceptable just because it's documented.
25. **Tests** cover each resolution path, retraction, `hide()` twice, a new trigger's notification, and the migration cases — not just field values. `PromoRegistryTests` includes the promo.
26. **pbxproj**: every new file is in both app targets, with no unrelated re-sorting.
