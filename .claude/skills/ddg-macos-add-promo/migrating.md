# Migrating shipping UI onto the queue

Use this when the promo already ships as UI presented by its own code: an update notification, a one-off popover, a banner some controller shows directly. Items 1–2 feed the decision sheet (SKILL.md Step 3), so do them **before** deciding fields. Items 3–6 are plan task D.

"No behavior change, just moving it into the queue" is almost never true by default. The queue imposes its own cooldowns, priority, timeouts and onboarding gate, and it is easy to ship four frequency changes while believing you shipped none.

## 1. Inventory the old path

From the legacy code, write down: what gated it, its frequency cap, where it anchored, its auto-dismiss duration, how hover behaved, which pixels it fired, and where it recorded "already shown". You can't tell whether behavior changed without this list.

## 2. Map each item onto the queue, and diff old against new

Each difference is a ❓ row on the decision sheet.

| Legacy concept | Where it goes | Trap |
|---|---|---|
| Frequency cap ("once per 7 days") | The `PromoResult` cooldown on each resolution path | Not preserved by default, and a medium+ promo is also floored by the global cooldown (`checkRules` in [reference.md](reference.md)) |
| "Should show?" gating | `isEligible` / `refreshEligibility()` | Must re-derive from current state, not from having observed an event |
| Auto-dismiss timer | `PromoType.timeoutInterval` | Base-type defaults are often shorter than the legacy value. The queue's timeout doesn't pause on hover; keeping hover-to-keep-open (`dismissPopoverUnlessHovering()` in `hide()`) still records the timeout result at the deadline, so a later CTA tap records nothing — fine when every path resolves the same way, a ❓ when the CTA path differs |
| *(nothing — the queue adds this)* | Onboarding gate | Triggers arriving before onboarding completes are discarded with no retry. (Restore has no onboarding check.) |
| A "has been shown" `UserDefaults` flag | Read-only check in `show()` returning `.retired` (item 4) | Promo history starts empty; skip this and everyone who saw the legacy UI sees it again |
| *(nothing — you add this)* | Kill switch (implementing.md task A) | The queue has no flag of its own, so without one the only off switch is a new release |
| Presentation call site | The delegate's `show()` | Delete it (item 3) |
| Pixels | The delegate | Say which move, which stay, and which now fire at a different moment |

An **external** migration keeps the owning system presenting; what you add is the observer. Its kill switch gates `isVisible`, so turning it off stops the queue coordinating, not the UI appearing.

## 3. Delete the legacy presentation path in the same change

The kill switch off means "the promo doesn't show", not "the old path shows instead". Don't gate the legacy call site on the flag, and don't leave both paths alive "until the rollout finishes" — that's two frequency caps, two sets of pixels, and states where both present. If you think a fallback is needed, that's a question for the user.

Remove the observer or `showXIfNeeded()` that presented it and the gating around its call site, and post the event it listened for as a `PromoTrigger`. Remove the old auto-dismiss timer too.

## 4. Retire the promo for users who already saw the legacy UI

Read the legacy flag in `show()` and return `.retired`: permanent, and unlike `.ignored()` it records no dismissal, so those users don't burn the global cooldown on a promo that never appeared. Let `force` bypass it so Force Show still previews the UI:

```swift
if !force, storage.didShowLegacyPopover == true {
    return .retired
}
```

Read it through `KeyedStorage` over a `StoringKeys` struct (`import Persistence`), not the deprecated `@UserDefaultsWrapper`. Declare the key in `UserDefaultsKeys` under `// MARK: - Promo Queue Legacy Flags` with its **existing raw string** — renaming it orphans the shipped value and re-shows the promo to everyone. Inject the store so tests use `InMemoryKeyValueStore`:

```swift
struct BookmarkToolbarPromoSettings: StoringKeys {
    let didShowLegacyPopover = StorageKey<Bool>(UserDefaultsKeys.bookmarksBarPromptShown, assertionHandler: { _ in })
}

init(..., storage: KeyedStorage<BookmarkToolbarPromoSettings>? = nil) {
    self.storage = storage ?? KeyedStorage(storage: UserDefaults.standard)
}
```

The promo reads the flag and never writes it — history is the record from now on — so name it as the legacy artifact it is (`didShowLegacyPopover`, not `promoShown`). Move every other reader, and any debug-menu action that clears it, off `UserDefaultsWrapper` too.

## 5. Don't strand the old code

Delete presenter methods whose only production caller you removed, or point the remaining caller (often a debug menu) at Force Show. Delete now-unread state, such as a `lastShownDate` nobody reads. Rename methods whose behavior changed — a `showXIfNeeded` that no longer shows is a trap. Fix doc comments that still describe the old cap.

## 6. Keep the diff honest

Every number that differs from shipping behavior must already be an answered ❓ on the decision sheet. If you find one during implementation, stop and ask.
