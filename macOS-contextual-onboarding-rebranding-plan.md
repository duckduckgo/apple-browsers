# Plan: macOS Contextual Onboarding Rebranding

## Context

iOS added a rebranded contextual onboarding by duplicating the view/factory layer under a `Rebranding/` folder, gated by `.onboardingRebranding` feature flag. Business logic (dialog manager, state machine) stays untouched. We port this to macOS by:

1. Adding the feature flag
2. Creating a rebranded factory + provider that switches between legacy and rebranded
3. Initially the rebranded factory delegates to the **same legacy views** — testable immediately
4. Then, one PR at a time, we replace each legacy view with its rebranded version

## CRITICAL TYPE DIFFERENCE

On macOS, `OnboardingRebranding.ContextualDaxDialogContent` requires:
- `title: NSAttributedString?` (NOT `AttributedString` or `String`)
- `message: NSAttributedString` (NOT `AttributedString` or `String`)

There is NO `String` convenience init on macOS. Every `title` and `message` must be wrapped in `NSAttributedString(string:)`.

## VERIFIED FACTS

- `BrowserTabViewController.swift` imports: `FeatureFlags`, `PrivacyConfig`
- All `UserText.ContextualOnboarding.*` keys exist at `macOS/DuckDuckGo/Common/Localizables/UserText.swift`
- macOS theme: `OnboardingTheme.macOSRebranding2026` (aliased as `.rebranding2026` via `#if os(macOS)`)
- macOS `applyOnboardingTheme` takes ONE parameter (no `stepProgressTheme`)
- `applyMaxDialogWidth` is iOS-only — does not exist on macOS
- `.scrollIfNeeded()` is iOS-only — does not exist on macOS
- `OnboardingSuggestedSearchesProvider` exists on macOS
- Background images are in the shared `Onboarding` package (`OnboardingRebrandingImages.Contextual.*`)
- `ContextualOnboardingBackgroundType` and `applyContextualOnboardingBackground` exist in shared package
- `OnboardingGradient` is the legacy background (used by `DefaultContextualDaxDialogViewFactory`)

---

## PR 1: Infrastructure Scaffold

Feature flag + FadeInView + RebrandedFactory (using LEGACY views) + Provider + BrowserTabViewController wiring.

Toggle flag OFF → legacy flow. Toggle flag ON → same legacy views routed through rebranded factory with red "REBRANDED" DEBUG badge.

### Step 1: Add Feature Flag

**File:** `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift`

- Add `case onboardingRebranding` after `case contextualOnboarding`
- `defaultValue`: no change (falls through to `default: false`)
- `supportsLocalOverriding`: add `.onboardingRebranding` to `return true` block
- `source`: add `case .onboardingRebranding: return .disabled`

### Step 2: Create Directories

```
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Components/
```

### Step 3: Create `FadeInView.swift`

**Path:** `Components/FadeInView.swift`

Simple SwiftUI wrapper that fades in content with 0.4s ease-in animation.

### Step 4: Create `RebrandedContextualDaxDialogsFactory.swift`

**Path:** `Rebranding/RebrandedContextualDaxDialogsFactory.swift`

Initially a **copy of `DefaultContextualDaxDialogViewFactory`** that:
- Uses the same legacy dialog views (OnboardingTrySearchDialog, OnboardingFirstSearchDoneDialog, etc.)
- Applies `.applyOnboardingTheme(.macOSRebranding2026)` to all views
- Adds a red "REBRANDED" DEBUG badge overlay

### Step 5: Create `ContextualDaxDialogsProvider.swift`

**Path:** `Rebranding/ContextualDaxDialogsProvider.swift`

Checks `featureFlagger.isFeatureOn(.onboardingRebranding)` and delegates to legacy or rebranded factory.

### Step 6: Update `BrowserTabViewController.swift`

Change default factory from `DefaultContextualDaxDialogViewFactory` to `ContextualDaxDialogsProvider`.

### Step 7: Add Files to Xcode Project + Build

### Testing PR 1
1. Build → zero errors
2. Flag OFF → old flow, no badge
3. Flag ON → same views with red "REBRANDED" badge
4. Walk through: TrySearch → SearchDone → TrySite → Trackers → Fire → HighFive

---

## PR 2: Rebranded TrySearch Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+TrySearch.swift`

`OnboardingRebranding.OnboardingTrySearchDialog` using `ContextualDaxDialogContent` with `NSAttributedString` title/message, `OnboardingBubbleView.withDismissButton`, `ContextualOnboardingListView`.

Update `RebrandedContextualDaxDialogsFactory.tryASearchDialog()` to use new view.

---

## PR 3: Rebranded TrySite Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+TrySite.swift`

`OnboardingRebranding.OnboardingTrySiteDialog` + `OnboardingTrySiteDialogContent` (reused by SearchCompleted follow-up).

Update factory.

---

## PR 4: Rebranded SearchCompleted Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+SearchCompleted.swift`

`OnboardingRebranding.OnboardingSearchDoneDialog` with `showNextScreen` state for follow-up transition to `OnboardingTrySiteDialogContent`.

Note: `onManualDismiss` signature changes to `(_ isShowingNextScreen: Bool) -> Void`.

Update factory.

---

## PR 5: Rebranded Trackers Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+Trackers.swift`

`OnboardingRebranding.OnboardingTrackersBlockedDialog` with follow-up transition to `OnboardingFireDialogContent`.

Note: `onManualDismiss` signature changes to `(_ isShowingNextScreen: Bool) -> Void`.

Update factory.

---

## PR 6: Rebranded Fire Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+Fire.swift`

`OnboardingRebranding.OnboardingFireDialog` + `OnboardingFireDialogContent` with bold "Fire Button" text via `NSMutableAttributedString`.

Update factory.

---

## PR 7: Rebranded EndOfJourney Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+EndOfJourney.swift`

`OnboardingRebranding.OnboardingEndOfJourneyDialog` with title, message, CTA button.

Update factory.

---

## PR 8: Rebranded AddFavorite Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+AddFavorite.swift`

`OnboardingRebranding.OnboardingAddFavorite` — simple bubble with message, no CTA.

Update factory (if wired into a dialog type).

---

## PR 9: Rebranded SubscriptionPromo Dialog

**New file:** `Rebranding/RebrandedContextualOnboardingDialogs+SubscriptionPromo.swift`

`OnboardingRebranding.OnboardingSubscriptionPromoDialog` with promoShield image, proceed/dismiss buttons.

Note: `OnboardingRebrandingImages.Contextual.promoShield` may need a macOS asset — use `EmptyView()` placeholder if unavailable.

Update factory.

---

## Files Summary

### New files (across all PRs):
```
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Components/FadeInView.swift                                    (PR 1)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualDaxDialogsFactory.swift          (PR 1)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/ContextualDaxDialogsProvider.swift                  (PR 1)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+TrySearch.swift       (PR 2)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+TrySite.swift         (PR 3)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+SearchCompleted.swift (PR 4)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+Trackers.swift        (PR 5)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+Fire.swift            (PR 6)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+EndOfJourney.swift    (PR 7)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+AddFavorite.swift     (PR 8)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualOnboardingDialogs+SubscriptionPromo.swift (PR 9)
```

### Modified files:
```
macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift   (PR 1)
macOS/DuckDuckGo/Tab/View/BrowserTabViewController.swift                  (PR 1)
macOS/DuckDuckGo/Onboarding/ContextualOnboarding/Rebranding/RebrandedContextualDaxDialogsFactory.swift  (PRs 2-9, incrementally)
```
