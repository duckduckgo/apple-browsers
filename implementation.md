# [iOS] Always Show Keyboard on New Tab Page: Implementation Plan

This plan builds on `requirements.md`. Its case matrix (§5) and open questions (§11) were updated on 2026-09-30 to match the code review below. Rows referred to here are §5 rows.

The kick-off hasn't happened yet, so the plan uses each **(confirm)** item's recommended answer, marked **⚑ Qn** with the §11 question numbers.

Paths are relative to `iOS/DuckDuckGo/` unless they start with `iOS/`. Some names are abbreviated:
- MVC: `Main/MainViewController.swift`
- MC: `Application/UICoordination/MainCoordinator.swift`
- LAH: `Application/UICoordination/LaunchActionHandler.swift`
- KP: `Application/UICoordination/KeyboardPresenter.swift`

## 1. Overview

### 1.1 How NTP keyboard focus is decided today

Seven places decide focus, and each follows its own rules.

| # | Where | When it runs | Rule | Focus call |
|---|---|---|---|---|
| A | `attachHomeScreen` (MVC:2346-2351, 2413) | Only when an NTP arrives through `newTab()` (`isNewTab: true`), including the idle-return NTP (MC:954) | `allowingKeyboard && onNewTab && !subscriptionPromotionPending && !chatPathCompletionPending` | `omniBar.beginEditing`, synchronous |
| B | `KeyboardPresenter.showKeyboardOnLaunch` (KP:40-53), called from LAH:130 | Standard launch, after auth and AutoClear (`Application/UICoordination/UIInteractionManager.swift:77-79`) | `onAppLaunch` and more than 20s in the background (not checked on a cold start). Applies to any tab. Skipped after an idle return with the New Tab treatment (LAH:121-123) | `enterSearch()` after 0.1s |
| C | `forgetAllWithAnimation` completion (MVC:7754-7765) | A burn whose options include `.tabs`, except Escape Hatch burns | `onNewTab`, not a Duck.ai tab, **and the "Search & Duck.ai" setting off** (`aiChatSettings.isAIChatSearchInputUserSettingsEnabled`) | `enterSearch()` after 0.3s |
| D | `onQuickFirePressed` (MVC:2556-2564) | The Control+Option+Backspace key command | `onAppLaunch`. The burn's `omniBar.endEditing()` (MVC:7988) undoes this on the next run loop, so C decides what the user sees | `enterSearch()`, synchronous |
| E | `restoreFocusModeAfterBurnIfNeeded` (MVC:2264-2271) | A single-tab burn from the Escape Hatch card (MVC:6547-6600) | Restores the focus state from before the burn and ignores both settings | `activateInput()` or `enterSearch()` |
| F | `ddgNewSearch` deep link (MC:785-787) | Search widget, Lock Screen and Control Center search, Siri "Open DuckDuckGo" (`AppIntents/AppShortcuts.swift:61-71`) | Always shows the keyboard, whatever the settings | `enterSearch()` |
| G | NTP onboarding dialogs (`NewTabPage/NewTabPageViewController.swift:403-425`) | Onboarding completion | Always shows the keyboard | `beginEditing` |

`enterSearch()` (MVC:2745-2750) does nothing while any view controller is presented. On iPhone, `beginEditing` is intercepted and opens a Unified Toggle Input (UTI) session instead. UTI doesn't open on Duck.ai tabs, and it restores the last Search/Duck.ai mode (`UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift:1316-1340`).

### 1.2 Where the shared decision lives

Add one pure value type, `NewTabPageKeyboardPolicy`, to `KeyboardPresenter.swift`. `Application/UICoordination` is a buildable folder, so the project file needs no changes. Two thin helpers on `MainViewController` apply the policy together with the existing dialog checks. Every flag-on path goes through them.

Paths E, F and G stay as they are. A only gets the App Launch OR for idle NTPs (PR 1). With the flag off, no caller reaches the policy.

### 1.3 Inputs

- **Landing kind:** app open, in-app landing, or after Fire.
- **Time in the background:** the 20s rule. `nil` means a cold start.
- **Settings:** `KeyboardSettings.onNewTab` and `onAppLaunch`.
- **Whether the current tab is an NTP** (`Tab.link == nil`).
- **Blockers:** onboarding in progress, a pending subscription promo, a pending chat-path completion, a launch prompt that has been committed or is presenting, and a presented screen (already handled by `enterSearch`).
- **After Fire only:** whether the tab is a Duck.ai tab, and the Search & Duck.ai setting during onboarding.
- **The feature flag**, checked at each call site.

Dismissal state is *not* an input. The decision runs only at landings, so a dismissal lasts until the next landing without any stored state (⚑ Q2).

## 2. Code findings the plan depends on

requirements.md already includes these; this section keeps the evidence.

1. **Fire uses New Tab, then skips the keyboard when Search & Duck.ai is on** (MVC:7754, 7759).
   - The guard was added in #1656 for the last onboarding step, but it applies to every burn.
   - The setting's key is `aichat.settings.showAIChatExperimentalSearchInput`, default off (`AIChat/AIChatSettings.swift:174-177, 403`). The onboarding picker, the new address bar picker and Duck.ai onboarding all turn it on.
   - Other things skip the keyboard too: a Duck.ai tab (7758), the Try AI dialog (2507), a fire-mode burn (the switcher stays up, 7811-7814), and a presented screen.
2. **Launch prompts race the launch keyboard.**
   - KP queues `enterSearch` at +0.1s. Then `onAppReadyForInteractions` calls `presentModalPromptIfNeeded` (`Application/AppLifecycle/AppStates/Foreground.swift:151-154`), which schedules the modal at +0.1s (`ModalPromptCoordination/ModalPromptCoordinationManager.swift:304, 332`).
   - `hasActiveOrPendingModalAttempt` (:121-126) is already true once a prompt is committed.
3. **Cold starts use the idle path.** `lastBackgroundDate` is stored in the file store (`Application/AppLifecycle/LastBackgroundDateStore.swift`, written at `Application/AppLifecycle/AppStates/Background.swift:59`) and read on cold starts too (`Foreground.swift:57, 83-85`). On a cold start, B gets `nil` and so skips the 20s rule (LAH:130).
4. **An idle return onto an existing NTP skips both settings.** LAH:121-123 returns early. The coordinator then returns early too, when the current tab is an NTP (MC:945-948) or a voice chat is active (MC:933-936). This is deliberate, and `iOS/DuckDuckGoTests/LaunchActionHandlerTests.swift:363` asserts it.
5. **Some NTPs are created with no keyboard:**
   - Close All Tabs burns directly (MVC:7557-7576).
   - Closing the last tab ends editing (MVC:2984-2988).
   - The Home button calls `closeTab(.createEmptyTabAtSamePosition)` (MVC:8682, 8795).

   Two related traps:
   - ⌘T on an NTP with no `TabViewController` probably falls through to `keyboardFind()` (`Main/MainViewController+KeyCommands.swift:204-213`). This is inferred, so check it on a device.
   - `TabDelegate.newTab(reuseExisting:)` forces `allowingKeyboard: false` (MVC:6942).
6. **Back can't reach an NTP** (`TabViewController.swift:5862-5866`).
7. **An idle return leaves presented screens up when the current tab is an NTP.** The dismissal in MVC:3827-3835 runs only on the path that creates a new NTP.
8. **The NTP session wide event records `launchKeyboardMode` before the launch keyboard appears** (MVC:2459; `Application/AppLifecycle/MainViewController+NewTabPageSession.swift:84-93`).
9. **Smaller facts:**
   - The Escape Hatch needs `IdleReturnEligibilityManager.isFeatureAvailable()` (`Application/AppLifecycle/IdleReturnEligibilityManager.swift:96-100`).
   - On iPad, After Inactivity defaults to Last Used Tab (`Application/AppLifecycle/AfterInactivityEffectiveOptionResolver.swift:55-66`), and multiple scenes are disabled (`Info.plist:218-219`).
   - Nothing checks for VoiceOver or a hardware keyboard.
   - The `showKeyboardAfterFireButton` work item (MVC:7764) is never cancelled.
   - The `showNextDaxDialog` branch (MVC:7752) is dead code.
   - Actions delivered while the app is in the foreground skip the auth and AutoClear pipeline (`Application/AppLifecycle/AppStateMachine.swift:194-200`).
   - After a failed first Face ID attempt, B may focus a hidden window (`Application/AppServices/AuthenticationService.swift:69-95`, not yet checked on a device).

## 3. Rows by pull request

| Rows | Flag-on behaviour | PR | Mechanism |
|---|---|---|---|
| 1a, 1b, 2, 9, 18 | App open follows `onNewTab \|\| onAppLaunch` on an NTP, and `onAppLaunch` elsewhere | 1 | KP flag branch → `showKeyboardOnAppOpenIfAllowed` |
| 4, 10 | Idle return onto an existing NTP focuses it; a presented screen stays up with no keyboard (⚑ Q10) | 1 | Delegate returns "kept NTP" → LAH falls through to KP |
| 3 | The idle NTP also honours App Launch (§4 table) | 1 | One condition in A |
| 16 (onboarding) | No app-open focus while onboarding | 1 | `isStillOnboarding()` in the helper |
| 16, 18 (launch prompts) | A pending launch prompt wins | 2 | `isModalPromptPending` check in KP's delayed block |
| 6, 8, 17 | After Fire: New Tab; the Search & Duck.ai skip applies only while onboarding (⚑ Q6) | 3 | New branch in C |
| 12, 13 | Close All Tabs, the last tab, Home; picking a different NTP in the switcher, or closing a tab onto an NTP (⚑ Q1) | 4 | `showKeyboardOnNewTabPageLandingIfAllowed` at user-facing call sites |
| 5, 7, 11, 14, 15, 19, 20 | Unchanged | – | – |
| 21 | Verify on a device | 1 (QA) | Contingency in PR 1, risk 2 |

## 4. Feature flag and remote config

Follow the pattern used by `defaultExistingIPhoneUsersToNewTabAfterIdle`, a default-off `iOSBrowserConfig` subfeature ramped in steps.

- **Subfeature:** in `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/iOSBrowserConfigSubfeature.swift`, add this at the end, after `sitePermissions`:
  ```swift
  /// https://app.asana.com/1/137249556945/task/1218357179163026
  case alwaysShowKeyboardOnNewTabPage
  ```
- **Flag:** in `FeatureFlag.swift`, add the case and its `Config`:
  ```swift
  case .alwaysShowKeyboardOnNewTabPage:
      Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.alwaysShowKeyboardOnNewTabPage))
  ```
  - The default stays `.disabled`, and `supportsLocalOverriding` stays at its default of `true`, so QA can toggle it in Settings → Debug → Feature Flags.
  - Add a source and default test next to the existing ones in `iOS/LocalPackages/FeatureFlags-iOS/Tests/FeatureFlagsTests/FeatureFlagsTests.swift`.
- **Remote config:** the privacy-configuration repository, under `iOSBrowserConfig.features`, uses the same shape as the embedded `iOS/Core/ios-config.json`. The embedded copy is refreshed by the weekly "Update embedded files" job, so don't edit it by hand.
  ```json
  "alwaysShowKeyboardOnNewTabPage": { "state": "internal" }
  ```
  Then, for the ramp:
  ```json
  "alwaysShowKeyboardOnNewTabPage": {
    "state": "enabled",
    "minSupportedVersion": "<first release with PRs 1–4>",
    "rollout": { "steps": [{ "percent": 2 }] }
  }
  ```
  - Add steps for 10, 25 and 100 percent over time. Each device rolls once and keeps the result, and new steps re-roll only the devices that aren't enrolled yet (`SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/AppPrivacyConfiguration.swift:148-185`).
  - To roll back, set `"state": "disabled"`.
  - Never raise `minSupportedVersion` after the ramp starts.
- **Tests:** use `MockFeatureFlagger(enabledFeatureFlags: flagOn ? [.alwaysShowKeyboardOnNewTabPage] : [])` (`iOS/SharedTestUtils/Mocks/BrowserServiceKit/MockFeatureFlagger.swift`). Set the flag explicitly in every test, and never read the live Privacy Configuration.

## 5. Pull requests

There are four stacked PRs, 1 → 2 → 3 → 4. Removing the flag and the old paths is a separate follow-up, about a month after the ramp reaches 100%, and isn't part of this plan.
- PRs 3 and 4 need only PR 1, so they can be reordered or reviewed in parallel.
- Remote config changes go to the privacy-configuration repository (§6).
- Tests go in `iOS/DuckDuckGoTests/LaunchActionHandlerTests.swift`. That file already has the keyboard mocks and uses Swift Testing, and using it avoids a `project.pbxproj` edit, because `DuckDuckGoTests` is a plain group (`project-structure.mdc`).

### 5.1 PR 1: Show the keyboard when the app opens onto an NTP (rows 1a, 1b, 2–5, 9–11, 18)

**Goal:** Every app open onto an NTP follows `onNewTab || onAppLaunch`. App opens onto any other tab keep the App Launch rule. Onboarding wins.

**Changes:**

1. **Flag:** as in §4.
2. **Policy** (`KeyboardPresenter.swift`):
   ```swift
   /// Keyboard rule for NTP landings behind `.alwaysShowKeyboardOnNewTabPage`.
   /// Callers check the flag; flag-off paths keep their own conditions.
   struct NewTabPageKeyboardPolicy {
       static let appOpenBackgroundThreshold: TimeInterval = 20   // moved from KeyboardPresenter
       let onNewTab: Bool
       let onAppLaunch: Bool
       init(onNewTab: Bool, onAppLaunch: Bool)
       init(settings: KeyboardSettings = KeyboardSettings())

       /// `nil` means a cold start.
       static func isAppOpen(lastBackgroundDate: Date?, now: Date = Date()) -> Bool
       func showsKeyboardOnAppOpen(onNewTabPage: Bool) -> Bool { onNewTabPage ? onNewTab || onAppLaunch : onAppLaunch }
   }
   ```
   The flag-off body of KP now calls `isAppOpen` in place of its private `shouldShowKeyboardOnLaunch`. The logic is the same.
3. **KeyboardPresenter:** `init(mainViewController:featureFlagger:)`, wired in `Foreground.swift:102`.
   - Flag off: today's body, unchanged.
   - Flag on:
     ```swift
     guard NewTabPageKeyboardPolicy.isAppOpen(lastBackgroundDate: lastBackgroundDate) else { return }
     if KeyboardSettings().onAppLaunch { PixelKit.fire(.keyboardOnAppLaunchUsedDaily, frequency: .dailyAndCount) } // same condition as today
     DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
         self.mainViewController.showKeyboardOnAppOpenIfAllowed()
     }
     ```
4. **MainViewController:**
   ```swift
   /// Extracted from attachHomeScreen (2346-2351). attachHomeScreen uses it unchanged.
   var isNewTabPageKeyboardBlockedByDialog: Bool { daxDialogsManager.subscriptionPromotionPending || isChatPathCompletionPending }

   /// Flag on only.
   func showKeyboardOnAppOpenIfAllowed() {
       let onNewTabPage = tabManager.currentTabsModel.currentTab?.link == nil
       guard NewTabPageKeyboardPolicy().showsKeyboardOnAppOpen(onNewTabPage: onNewTabPage) else { return }
       if onNewTabPage, daxDialogsManager.isStillOnboarding() || isNewTabPageKeyboardBlockedByDialog { return }
       enterSearch()   // no-op while the tab switcher, Settings, etc. are presented (row 11, ⚑ Q10)
   }
   ```
5. **LaunchActionHandler:** add `featureFlagger: FeatureFlagger` to the initializer, wired in `Foreground.swift:98-106`. In the `.ntp` case:
   ```swift
   let keptCurrentNewTabPage = idleReturnDelegate?.showNewTabPageAfterIdleReturn(timeAwayMs: timeAwayMs) ?? false
   guard keptCurrentNewTabPage, featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage) else { return }
   // Falls through to keyboardPresenter.showKeyboardOnLaunch (rows 4, 1b).
   ```
6. **IdleReturnLaunchDelegate:** change the method to `@discardableResult func showNewTabPageAfterIdleReturn(timeAwayMs: Int?) -> Bool`, which returns `true` only in the kept-NTP branch (MC:945-948). The voice-session branch and the branch that creates an NTP return `false`, so the voice-chat exclusion is kept.
7. **`attachHomeScreen`** (row 3, §4 table):
   ```swift
   let settingAllows = openedAfterIdle && featureFlagger.isFeatureOn(.alwaysShowKeyboardOnNewTabPage)
       ? NewTabPageKeyboardPolicy().showsKeyboardOnAppOpen(onNewTabPage: true)
       : KeyboardSettings().onNewTab
   ```
   Everything else in `willBeginEditing` stays the same.
8. **⚑ Q8 (optional; default: leave out):** if the ramp is judged on the NTP session wide event, add `noteKeyboardRaisedOnArrival()` to `NewTabPageSessionInstrumentation`. Call it from `showKeyboardOnAppOpenIfAllowed` so that `launchKeyboardMode` becomes `.up` when the visit has no actions yet. This adds no new pixel, and takes about 0.5 day.

**Flag off:**
- KP runs today's body.
- LAH still returns early for `.ntp`.
- `attachHomeScreen` still reads `onNewTab`.
- The extracted `isNewTabPageKeyboardBlockedByDialog` evaluates the same two conditions.
- The delegate's new return value is ignored.

**Tests** (Swift Testing; set the flag explicitly in each test):

| Test | Rows |
|---|---|
| `showsKeyboardOnAppOpen`, table-driven over all 8 combinations of `onNewTab` × `onAppLaunch` × `onNewTabPage` | 1a, 2, 18, §4 table |
| `isAppOpen`: `nil` → true; 21s → true; 20s and 5s → false | 1a, 2, 5 |
| LAH, flag off: `.ntp` treatment with delegate result `true` → keyboard presenter **not** called. Keep the existing test at :363 and parameterise its flag | 4 (today) |
| LAH, flag on: `.ntp` treatment with result `true` → called with the date, or with `nil` when `isFirstForeground` | 4, 1b, 9 |
| LAH, flag on: `.ntp` treatment with result `false` → not called | 3, voice chat |
| LAH, flag on and off: `.lut` treatment and no idle return → called | 2, 18 |

`MockIdleReturnLaunchDelegate` needs a configurable return value. Rows 10 and 11 are covered by QA, because `MainViewController` and `MainCoordinator` have no unit harness.

**Manual QA** (internal build; turn the flag on in Settings → Debug → Feature Flags):
- **Fast inactivity:** in Settings → Debug → "Idle Return NTP", set the threshold to 10s (`Settings/Debug/IdleReturnNTPDebugView.swift`). Run each case below with both After Inactivity options.
1. Kill the app while on an NTP and relaunch within 10s → keyboard (row 1a). Kill it, wait 15s and relaunch → keyboard (1b).
2. Set the threshold to 120s. Background for 30s on an NTP → keyboard (row 2). Background for 5s → state unchanged (row 5).
3. With the threshold at 10s: if the last tab is an NTP → keyboard (row 4). If the last tab is a website → Escape Hatch NTP with the card and keyboard (row 3). Repeat with both settings on (the report) and with New Tab off / App Launch on (keyboard); with both off → no keyboard.
4. Enable "Clear on app exit" for tabs and data, then relaunch → keyboard (row 9).
5. Open the Tab Manager, then background for 30s → the switcher stays and there's no keyboard (row 11). Background past the threshold with the current tab an NTP → the switcher stays (⚑ Q10). With a website → NTP with keyboard (row 10).
6. **Fresh install:** during contextual onboarding, background for 30s and return → no keyboard over the Dax dialogs.
7. **App lock on:** successful Face ID → keyboard after unlock. Cancel the first prompt, then unlock → record the result (row 21, risk 2).
8. Test with VoiceOver on, with a hardware keyboard (simulator), on iPad, in landscape, and with the NTP Redesign flag on and off.
9. Current tab is a Duck.ai chat with App Launch on → unchanged. Search widget and Siri "Open DuckDuckGo" → unchanged (row 19).
10. Turn the flag off and repeat steps 1–4 → today's behaviour.

**Risks:**
1. Until PR 2 lands, a launch prompt can open over the keyboard for internal testers.
2. **App lock:** focus can be lost after a failed first Face ID attempt. If step 7 confirms it, call `showKeyboardOnAppOpenIfAllowed()` from the unlock completion (`Application/AppServices/AuthenticationService.swift:90-95`) behind the flag, in this PR.
3. **Flicker:** the Redesign's resting state hides the address bar and reveals it on focus, so a late focus can flash. Don't confuse this with the known post-inactivity flash.
4. **VoiceOver:** focus jumps to the address bar on every NTP app open.

### 5.2 PR 2: Hold the launch keyboard while a launch prompt is pending (rows 16, 18)

**Goal:** A launch prompt that's about to show wins over the app-open keyboard.

**Changes:**
- Add `var hasActiveOrPendingModalAttempt: Bool { get }` to `ModalPromptCoordinationManaging`. The implementation already exists at `ModalPromptCoordinationManager.swift:121`. Update `iOS/SharedTestUtils/Mocks/DuckDuckGo/ModalPromptCoordination/MockModalPromptCoordinationManager.swift`.
- Add `var isModalPromptPending: Bool` pass-throughs to `PromoCoordinationService` (`Application/AppServices/PromoCoordinationService.swift`) and `MainCoordinator`.
- `KeyboardPresenter.init` gains `isModalPromptPending: @escaping () -> Bool`, wired in `Foreground.swift:102` as `{ appDependencies.mainCoordinator.isModalPromptPending }`.
- In the flag-on delayed block:
  ```swift
  // The launch prompt is committed synchronously right after this call and presented 0.1s later.
  guard !self.isModalPromptPending() else { return }
  ```
  This applies to websites too (row 18), because a keyboard under a modal is never wanted.

**Flag off:** KP's legacy body doesn't read the new closure. The new protocol property is read-only.

**Tests:**
- `PromoCoordinationService.isModalPromptPending` mirrors the mock manager.
- If `iOS/DuckDuckGoTests/ModalPromptCoordination/ModalPromptCoordinationManagerTests.swift` doesn't cover it yet, add cases where `hasActiveOrPendingModalAttempt` is true straight after a legacy or coordinated `presentModalPromptIfNeeded` commits a prompt.

**Manual QA:**
1. Reset the promo cooldown (promo debug screen) so a prompt is eligible, then cold start onto an NTP → the prompt shows with no keyboard under it. After you close it → no keyboard (⚑ Q5).
2. Repeat with the `promoPresentationCoordination` flag on and off.
3. Repeat with a website tab and App Launch on.
4. Tap a notification that opens a modal (for example VPN) → no keyboard under it.

**Risks:** in coordinated mode, lease acquisition may not have committed within 0.1s. If QA step 2 fails, also treat `modalAttemptPhase == .evaluating` as pending.

### 5.3 PR 3: Show the keyboard on the NTP after Fire (rows 6–8, 16, 17)

**Goal:** Every burn that lands on an NTP follows New Tab. The Search & Duck.ai suppression stays only during onboarding. Escape Hatch burns keep restoring focus.

**Changes:**
- Policy:
  ```swift
  func showsKeyboardAfterFire(onDuckAITab: Bool, searchInputToggleOn: Bool, stillOnboarding: Bool) -> Bool {
      onNewTab && !onDuckAITab && !(searchInputToggleOn && stillOnboarding)   // ⚑ Q6
  }
  ```
- In `forgetAllWithAnimation`'s completion (MVC:7752-7765), add a flag-on branch before today's `else if`:
  ```swift
  } else if flagOn, request.options.contains(.tabs), !isEscapeHatchBurn(request), !suppressPostFireKeyboard {
      // same 0.3s DispatchWorkItem, stored in showKeyboardAfterFireButton
      guard NewTabPageKeyboardPolicy().showsKeyboardAfterFire(
                onDuckAITab: currentTab?.isAITab == true,
                searchInputToggleOn: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
                stillOnboarding: daxDialogsManager.isStillOnboarding()),
            !isNewTabPageKeyboardBlockedByDialog else { return }
      enterSearch()
  } else if !flagOn, /* today's condition, unchanged */ {
  ```
- **Quick Fire:** no change. Verify on a device that D's App Launch focus is undone (MVC:7988). If it isn't, wrap MVC:2561 in `!flagOn`.
- **Escape Hatch burn (row 7):** no change (⚑ Q4).
- A fire-mode burn leaves the switcher up, so it isn't an NTP landing; no change.

**Flag off:** today's `else if` runs exactly as before.

**Tests:** a table-driven `showsKeyboardAfterFire`:
- Search & Duck.ai off or on, outside onboarding → true (rows 6, 8)
- On, during onboarding → false (row 16)
- Duck.ai tab → false (row 17)
- New Tab off → false

**Manual QA:**
1. Fire from the toolbar with "Search only", and with "Search & Duck.ai" → keyboard. With Search & Duck.ai, the input opens in the last used mode.
2. Fire from a Duck.ai tab → a new chat, with no focus on search.
3. Burn in fire mode → the switcher stays.
4. Burn from the Escape Hatch card, starting both focused and unfocused → that state is restored.
5. Quick Fire (Control+Option+Backspace in the simulator) with App Launch on and off → keyboard follows New Tab.
6. Fire widget or Control Center fire → keyboard.
7. Fresh install, fire onboarding step with each address bar choice → no keyboard under the Try AI dialog; the end of onboarding is unchanged.
8. Tap a favorite within 0.3s of a burn ending → note any keyboard over the page (risk 1).
9. Flag off → today's behaviour.

**Risks:**
1. The 0.3s work item is never cancelled, and more users now get it. If QA step 8 reproduces, cancel `showKeyboardAfterFireButton` in `transitionTo(tab:from:)`.
2. `isStillOnboarding()` may be true for longer than the dialog the original guard targeted. That only keeps today's behaviour for users in onboarding.

### 5.4 PR 4: Show the keyboard on in-app NTP landings (rows 12–15)

**Goal:** New tab from every entry point, plus (⚑ Q1) picking a different NTP in the Tab Manager and a user closing a tab onto an NTP.

**Changes:**
- **Policy:** `var showsKeyboardOnInAppLanding: Bool { onNewTab }`.
- **MainViewController:**
  ```swift
  /// Flag on only. An in-app landing on an NTP that didn't come through `newTab()`.
  func showKeyboardOnNewTabPageLandingIfAllowed() {
      guard tabManager.currentTabsModel.currentTab?.link == nil,
            NewTabPageKeyboardPolicy().showsKeyboardOnInAppLanding,
            !isNewTabPageKeyboardBlockedByDialog else { return }
      enterSearch()
  }
  private var focusesNewTabPageAfterTabSwitcherDismissal = false   // one-shot
  ```
- **Row 12 call sites**, all behind the flag:
  - Home button (MVC:8682, 8795), after `closeTab`.
  - Close All Tabs in normal mode (MVC:7557-7575): set the one-shot flag before `dismissIfPossible()`.
  - Closing the last tab in the switcher, then dismissing it, is handled by the tab switcher hook below.
- **Tab switcher (⚑ Q1):** the switcher reports the selection *before* it dismisses (`TabSwitcherViewController.swift:692-697`), and `enterSearch` no-ops while it's still presented. So:
  - In `tabSwitcher(_:didFinishWithSelectedTab:)`, after the same-tab guard (MVC:7405), set the one-shot flag when the new current tab is an NTP.
  - Consume and clear the flag in `tabSwitcherDidDismiss` (MVC:7394), which runs from the dismissal completion (`TabSwitcherViewController.swift:699-701`).
  - Tapping the same NTP, or Done, isn't a landing.
- **Closing a tab onto an NTP (⚑ Q1):** call the helper after `closeTab` returns. `updateCurrentTab` has already ended editing (MVC:2988). Call sites:
  - ⌘W (`Main/MainViewController+KeyCommands.swift:226-232`)
  - iPad tab bar close (`TabsBarViewController.swift:1002`)
- **Don't hook `closeTab`, `tabDidRequestClose` (MVC:6872) or `transitionTo` globally.** Programmatic flows also call them: burns, the Escape Hatch "Return to" card (MVC:6658), Back closing a child tab, error pages and Duck Player (the `TabViewController.swift` callers). Swiping onto an NTP goes through `selectTab` → `transitionTo` and stays unfocused (⚑ Q1).
- **⌘T:** verify on a device. If it does nothing on an NTP, call `newTab()` whenever `isShortcutEnabled()` is true, behind the flag (`Main/MainViewController+KeyCommands.swift:208-212`).
- If ⚑ Q1 is "no", keep only the row 12 call sites.

**Flag off:** no call site runs, and the one-shot flag is never set.

**Tests:** `showsKeyboardOnInAppLanding` for New Tab on and off (rows 12 and 13). The call sites are covered by QA.

**Manual QA:**
1. Every explicit new-tab entry point (toolbar, switcher +, long-press menus, browsing menu, iPad tab bar +, swipe past the last tab, ⌘T, ⌘N) → keyboard.
2. Close All Tabs → keyboard after the switcher closes. Close the last tab from the switcher and dismiss → keyboard. Home button → keyboard.
3. Tab switcher: pick a different NTP → keyboard. Pick the same NTP, or tap Done → no keyboard.
4. Close the current tab onto an NTP with ⌘W or the iPad × → keyboard. Swipe onto an NTP → no keyboard.
5. Settings → back → no keyboard (row 15). Dismiss, then stay → stays dismissed (row 14).
6. Test during onboarding and with a subscription promo pending → the dialog wins.
7. Flag off → today's behaviour.

**Risks:**
1. The keyboard can pop during the switcher's collapse animation. If it looks wrong, delay the helper to the next run loop.
2. An extra call site may be missed. Grep for `closeTab(` and `transitionTo(` when implementing.

## 6. Rollout (remote config only)

1. After PR 1 merges: set `"state": "internal"` and dogfood.
2. After the release containing PRs 1–4 is widely adopted: set `"enabled"` with `minSupportedVersion` set to that release, then ramp 2 → 10 → 25 → 100 percent over about two weeks, checking at each step.
3. Watch feedback volume, `m_keyboard_on_app_launch_used`, the `m_ntp_after_idle_*` pixels, and the NTP session wide event (only after PR 1 change 8 ships; ⚑ Q8).
4. Pause by holding the steps. Roll back with `"state": "disabled"`.
5. Don't overlap the ramp with another NTP rollout or experiment, including the NTP Redesign (⚑ Q9).
6. Tell the teams that depend on this change when the ramp starts. There's no in-app messaging.

## 7. Estimates

| PR | Estimate | Notes |
|---|---|---|
| 1 | 2 days | Includes the device QA; +0.5 day if ⚑ Q8 adds the instrumentation fix |
| 2 | 0.5 day | |
| 3 | 0.5 day | Quick Fire needs no code |
| 4 | 1 day (0.5 if ⚑ Q1 = no) | |
| Rollout | 0.5 day of work over about 3–4 calendar weeks | Waits for release adoption |
