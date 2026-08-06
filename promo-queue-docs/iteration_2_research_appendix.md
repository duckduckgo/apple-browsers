# Appendix — Machine-Generated Ground-Truth Reports (Jul 10, 2026)

Companion to `iteration_2_research.md` / `iteration_3_research.md`. Two agent-produced reports over the local checkouts (`apple-browsers` @ `bartosz/promo-queue`, `remote-messaging-config` @ main). **Trust code over this appendix on any conflict; re-verify `file:line` cites before relying on them.**

---

## Part 1 — RMF Capability Map (iOS-focused, cross-platform notes)

Sources: config repo `/Users/bkunat/Desktop/ddg-workspace/remote-messaging-config` (schemas: ios `schemas/ios/schema.json`, macos `schemas/macos/schema.json` — **no android/windows schemas exist in the repo**), client framework `/Users/bkunat/Desktop/ddg-workspace/apple-browsers/SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/`, iOS app `iOS/DuckDuckGo/`, macOS app `macOS/DuckDuckGo/`. Prod endpoints: `staticcdn.duckduckgo.com/remotemessaging/config/v1/{ios,android,macos,windows}-config.json` (`remote-messaging-config/README.md:17-26`); iOS DEBUG builds fetch `samples/ios/sample1.json` from GitHub (`iOS/DuckDuckGo/RemoteMessagingClient.swift:39-45`).

### 1. Message templates & surfaces

**Client enum `RemoteMessageModelType`** (`SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:212-243`); JSON names in `Model/JsonRemoteMessagingConfig.swift:141-147`:

| JSON `messageType` | Client case | Payload | iOS schema | macOS schema |
|---|---|---|---|---|
| `small` | `.small` | title, description (no image, no buttons) | ✅ | ✅ |
| `medium` | `.medium` | + placeholder, optional `imageUrl` | ✅ | ✅ |
| `big_single_action` | `.bigSingleAction` | + primaryActionText/primaryAction | ✅ | ✅ |
| `big_two_action` | `.bigTwoAction` | + secondaryActionText/secondaryAction | ✅ | ✅ |
| `promo_single_action` | `.promoSingleAction` | actionText/action (single centered CTA) | ✅ | ❌ (client-blocked: `isSupported == false`, `macOS/DuckDuckGo/RemoteMessaging/ActiveRemoteMessageModel.swift:227-237`) |
| `cards_list` | `.cardsList` | title, optional placeholder/imageUrl, `listItems[]`, primaryActionText/primaryAction | ✅ | ❌ (schema lags client) |

**cards_list item types** (`JsonRemoteMessagingConfig.swift:96-99`, model `RemoteMessageModel.swift:318-352`): `featured_two_line_single_action_list_item` (max one, forced first — `Mappers/JsonToRemoteMessageModelMapper.swift:543-546`, `RemoteMessagingConfigProcessor.swift:92-127`), `two_line_list_item`, `section_title` (carries `itemIDs`; section pruned if all referenced items filtered out — `RemoteMessagingConfigMatcher.swift:218-244`). Items support **per-item `matchingRules`/`exclusionRules`** (`RemoteMessagingConfigMatcher.swift:60-75`); duplicate item ids dropped.

**Surfaces.** `RemoteMessageSurfaceType` OptionSet: `newTabPage`, `modal`, `dedicatedTab`, `tabBar` (`RemoteMessageModel.swift:193-210`); JSON `surfaces: ["new_tab_page"|"modal"|"dedicated_tab"|"tab_bar"]` optional array on the message (ios schema:38-44). Surface eligibility = declared array ∩ **client-hardcoded per-template allowlist** (`RemoteMessaging/RemoteMessagingSurfacesProviding.swift`):

- **iOS** (`iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-32`): banners (small/medium/big*/promo) → `.newTabPage` **only**; `cardsList` → `.modal` **only**. iOS has **no tab_bar and no dedicated_tab support**.
- **macOS** (`macOS/DuckDuckGo/RemoteMessaging/DefaultRemoteMessagingSurfacesProvider.swift:24-31`): banners → `[.newTabPage, .tabBar]`; `cardsList` → `.dedicatedTab` — but **nothing on macOS ever fetches `.dedicatedTab`** (only `[.newTabPage, .tabBar]` at `ActiveRemoteMessageModel.swift:221`), so cards_list is currently unrenderable on macOS.
- If `surfaces` absent (all pre-2025 messages): defaults to `.newTabPage` if supported, else the template's supported set (`JsonToRemoteMessageModelMapper.swift:211-219`). Declared-but-unsupported surfaces dropped with a log; message discarded if none remain (`:220-231`).
- macOS tab bar additionally only *renders* `bigSingleAction` with a `survey` primaryAction (`macOS/DuckDuckGo/TabBar/ViewModel/TabBarRemoteMessageViewModel.swift:64-90`), plus id-pinned `macos_permanent_survey_tab_bar` (`TabBar/Model/TabBarRemoteMessage.swift:22`, special-cased `ActiveRemoteMessageModel.swift:131-138`).

**Surface is declared in the schema, but the template→surface matrix is hardcoded per platform in the app target, with one more renderer-level filter on top.**

### 2. Matching attributes

**Full client vocabulary** — `AttributesKey`, 44 keys (`Mappers/JsonToRemoteMessageModelMapper.swift:24-68`); structs in `Model/MatchingAttributes.swift`; three matchers composed in `RemoteMessagingConfigMatcher.swift:35-49`:

- **Device** (`Matchers/DeviceAttributeMatcher.swift:37-48`): `locale`, `osApi`, `formFactor`.
- **App** (`Matchers/AppAttributeMatcher.swift`): common — `isInternalUser`, `appId`, `appVersion` (range), `atb`, `appAtb`, `searchAtb`, `expVariant`. Desktop-only — `installedMacAppStore`, `canUpgradeOS` (:72-81).
- **User** (`Matchers/UserAttributeMatcher.swift`; `#if os` typealias :24-28):
  - **Common** (:318-396): `appTheme`, `bookmarks`, `favorites`, `daysSinceInstalled`, `emailEnabled`, `daysSinceNetPEnabled`, `pproEligible`, `pproSubscriber`, `pproDaysSinceSubscribed`, `pproDaysUntilExpiryOrRenewal`, `pproPurchasePlatform`, `pproSubscriptionStatus`, `pproSubscriptionTier`, `subscriptionFreeTrialActive`, `duckPlayerOnboarded`, `duckPlayerEnabled`, `interactedWithMessage` (**dismissed** ids), `messageShown` (**shown** ids), `allFeatureFlagsEnabled`, `daysSinceDuckAiUsed`.
  - **iOS-only** (:117-138): `widgetAdded`, `syncEnabled`, `ntpAfterIdleState`, `shouldShowWinBackOfferUrgencyMessage`, `isFreemiumPIREligible`, `freemiumPIRDidActivate`, `freemiumPIRFirstScanResult`, `isCurrentPIRUser`.
  - **macOS-only** (:213-234): `pinnedTabs`, `customHomePage`, `isCurrentFreemiumPIRUser`, `isCurrentPIRUser`, `interactedWithDeprecatedMacRemoteMessage`.
- **Schema drift:** iOS schema (:389-429) lists 41 attributes — missing recent client adds (`pproSubscriptionTier`, `ntpAfterIdleState`) and includes macOS-isms that no-match on iOS. Android/Windows vocab differs (config-repo `templates/rules/attributes/`: `flavor`, `installedGPlay`, `daysUsedSince`, `searchCount`, `webview`, `defaultBrowser`).
- **Value matchers** (`MatchingAttributes.swift:305-409` + `Model/MatchingAttributesPrototypes/`): bool/int/string exact, string-array membership, int range, version range, `ArrayContainsAllMatching`.
- **Forward compat:** unknown attribute key → `UnknownMatchingAttribute` → per-config `fallback` bool or skip (`JsonToRemoteMessageModelMapper.swift:418-423`, `RemoteMessagingConfigMatcher.swift:88-91`). **New targeting dimensions require a client release.**
- **Percentile targeting:** rule-level `targetPercentile: { before: 0..1 }` (schema:435-446); lazily-assigned persisted `Float.random(0...1)` per entity id (`RemoteMessagingPercentileStoring.swift:38-50`; checked `RemoteMessagingConfigMatcher.swift:144-151`). No date windows, no holdbacks.
- **Cohorts/experiments: none.** `allFeatureFlagsEnabled` excludes cohort/experiment flags (`flag.cohortType == nil` filter — `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:165-167`). RMF globally gated by privacy-config `remoteMessaging` (`RemoteMessagingAvailabilityProviding.swift:43-46`).
- iOS matcher inputs wired in `RemoteMessagingConfigMatcherProvider.refreshConfigMatcher` (`iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:78-209`).

### 3. Actions

`RemoteAction` (`RemoteMessageModel.swift:368-378`); JSON `type` values (`JsonRemoteMessagingConfig.swift:150-157`; ios schema:577-580): `share`, `url`, `url_in_context`, `appstore`, `dismiss`, `survey` (+`queryParams`), `navigation`.

- **Survey param whitelist** (`Mappers/RemoteMessagingSurveyActionMapping.swift:21-39`): `atb`, `var`, `delta`, `mo`, `ddgv`, `osv`, `locale`, `last_search_state`, ppro_* set, `vpn_first_used/last_used`. Unsupported param ⇒ message **discarded** (`JsonToRemoteMessageModelMapper.swift:335-341`).
- **`NavigationTarget`** (`RemoteMessageModel.swift:356-366`): `duckai.settings`, `settings`, `settings.general`, `feedback`, `sync`, `import.passwords`, `appearance`, `pir.main`, `softwareUpdate`. iOS schema allows all except `softwareUpdate` (schema:296); iOS handles all but `softwareUpdate` via `DefaultMessageNavigator` (`iOS/DuckDuckGo/MessageNavigator.swift:50-73`). macOS schema only `feedback`+`softwareUpdate`; macOS NTP handles `feedback`/`pir.main`/`softwareUpdate` (`macOS/DuckDuckGo/NewTabPage/Features/ActiveRemoteMessageModel+NewTabPage.swift:56-66`).
- **iOS execution** (`iOS/DuckDuckGo/RemoteMessagingActionHandling.swift:63-86`): `share`→activity sheet; `url`→new tab; `urlInContext`→embedded webview; `appstore`→App Store app; `survey`→tab with refreshed `last_search_state`; `navigation`→`MessageNavigator` (presentation styles :25-35); `dismiss`→surface-level.
- Android action vocab differs (config-repo `templates/messages/content/action/`): `playstore`, `default_browser`, `website`, `search`, `dismiss`.

### 4. Selection & lifecycle semantics

**Pipeline** (`RemoteMessagingProcessing.fetchAndProcess`, `RemoteMessagingProcessing.swift:81-107`): flag gate → fetch (ETag-aware, `RemoteMessagingConfigFetcher.swift:41-64`) → rebuild matcher with fresh values → process → save → `remoteMessagesDidChange`.

**Re-evaluation** (`RemoteMessagingConfigProcessor.swift:49-85`): config `version` changed, OR stored config `invalidate`d (set on every dismissal — `RemoteMessagingStore.swift:337`), OR last evaluation >24h (`Model/RemoteMessagingConfig.swift:38-45`). Fetch cadence — iOS: every foreground (`Foreground.swift:157` → `RemoteMessagingService.swift:114-147`, prefetches remote images), config-assets updates (`AppConfigurationFetch.swift:188`), BG task min 4h (`RemoteMessagingClient.swift:37-38,127-196`). macOS: 30-min timer.

**Selection** (`RemoteMessagingConfigMatcher.evaluate`, `RemoteMessagingConfigMatcher.swift:51-78`): drop dismissed ids → iterate **in config-file order** → first full match wins. **No priority field — JSON order is priority.** Empty rules auto-match (:176-179).

**Storage** (`RemoteMessagingStore.swift`, Core Data): message {id, JSON blob, status scheduled/dismissed/done, shown, firstShownDate, surfaces bitmask}; config {version, evaluationTimestamp, invalidate}.

- **Exactly one `scheduled` message at a time, across ALL surfaces**: `saveProcessedResult` stores the single winner; other scheduled → `done`; done-and-never-shown deleted (`RemoteMessagingStore.swift:92-125,443-506`). "Queueing" is emergent: dismiss → invalidate → next refresh promotes next eligible.
- **Shown accounting**: `updateRemoteMessage(asShown:)` once (:372-408). NTP marks shown on appearance (`HomePageConfiguration.swift:99-123`, pixels `m_remote_message_shown[_unique]`); **modal (What's New) marks shown *and dismissed* on present** — one-shot (`iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:67-75`).
- **Dismissal is permanent** (feeds `interactedWithMessage`); only debug reset undoes.
- **Caps/cooldowns: none in RMF.** Only `displayConditions.trigger: "after_idle"` (NTP-built-`openedAfterIdle` only — `HomePageConfiguration.swift:71-82`, `RemoteMessageModel.swift:26-41`; macOS always fetches `.noTrigger` → after-idle never shows there, `RemoteMessagingStoring.swift:40`) and `displayConditions.dismissAfterDaysShown: N` (≥1, from `firstShownDate` — `RemoteMessagingStore.swift:255-262`, schema:298-317). No impression counts, no per-message frequency, no global spacing.
- iOS **modal surface** inherits external throttling from ModalPromptCoordination: privacy-config global cooldown (`PromoCoordinationService.swift`), fixed priority WinBack → SubscriptionPromo (reinstaller) → SubscriptionPromo (existing user) → AddressBarPicker → DefaultBrowser → **What's New (RMF)** → CookiePopup opt-in, standard-launch and provider-level onboarding gates, trigger `Foreground.swift`.

### 5. What's live in production (`live/`)

**iOS** (`live/ios-config/ios-config.json`, v114 — 24 messages / 27 rules; same message id repeated with different single-locale rules as the locale-split idiom):

| id | template | surface | targeting gist |
|---|---|---|---|
| `ios_privacy_pro_exit_survey_1` ×8 | big_single_action (survey) | default NTP | subscriber + platform + expiring/expired + appVersion + locale |
| `ios_privacy_pro_subscriber_survey_1` ×8 | big_single_action (survey) | default NTP | subscriber ≥30d + active, excl. exit-survey-dismissed |
| `ddg_ios_survey_1` | big_single_action (survey) | default NTP | daysSinceInstalled + en-US, **percentile <0.6** |
| `ios_pir_freemium_entry_point` / `_scan_complete_results` / `_no_results` | big_single_action (`navigation:pir.main`) | `["new_tab_page"]` | freemium-PIR attrs |
| `ios_winback_offer_urgency` | big_two_action (url + dismiss) | default NTP | `shouldShowWinBackOfferUrgencyMessage` |
| `ios_ntp_after_idle_existing_users_2026` | big_two_action (dismiss + `navigation:settings.general`) | `["new_tab_page"]` | appVersion + daysSinceInstalled; **{after_idle, dismissAfterDaysShown: 5}**; 25 translations |
| `funnel_newtab_adblockermf_ios1a/2a` | medium (**remote `imageUrl`**) | default NTP | locale + appVersion + duckPlayerEnabled, excl. sibling-interacted; 25 translations |

Nothing live on iOS uses `modal`/`cards_list`, `promo_single_action`, `share`, `appstore`, or `urlInContext` today. **macOS** (v58): ppro surveys ×7 locales, id-pinned tab-bar survey, critical-update/url + appstore/sparkle update messages, Big Sur EOS trio (`navigation:softwareUpdate`, `canUpgradeOS`), adblocker mediums. **Android** (v106): OS-deprecation (`osApi`), surveys with percentiles 0.1–0.2. **Windows** (v64): surveys + preview/sync promos (windows-only attrs `flavor`/`defaultBrowser`/`sync`).

### 6. Gaps vs "route ALL app promos through RMF"

1. **Surface coverage (iOS)**: only NTP card + launch modal. No tab bar/dedicated tab; none of: settings rows (`SettingsCompleteSetupView`), sync promo section headers, Duck Player pills, autofill list promos, badges, half-sheets, notifications. Legacy local NTP messages are dead code (`HomeMessageStorage.messagesToBeShown` returns `[]`, `iOS/DuckDuckGo/HomeMessageStorage.swift:30-33`). New surface = OptionSet bit + schema enum + per-platform provider + renderer + store-bitmask migration.
2. **Single-scheduled-message bottleneck**: one scheduled message across all surfaces; NTP banner and What's New modal cannot be live simultaneously; config-order winner monopolizes until dismissed/expired. **Core structural constraint.**
3. **No frequency capping/pacing**: no impression caps, no cross-message cooldown, no start/end dates (campaign windows = config edits); iOS modal cooldown lives outside RMF (ModalPromptCoordination). Current iOS product code has no NTP/modal arbitration; iteration 1 now proposes a targeted app-level permit coordinator rather than macOS-style `ExternalPromo` integration. macOS's observation-only comparison remains at `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+RemoteMessage.swift` and `RemoteMessagePromoDelegate.swift:26-81`.
4. **Targeting ceiling**: release-bound attribute vocabulary; no experiments/cohorts; static per-message percentile.
5. **Localization**: inline `translations` per message (exact-locale → language fallback — `JsonToRemoteMessageModelMapper.swift:440-455`, `RemoteMessageModel.swift:101-190`); heavy duplication; ×8-copies idiom exists because per-rule copy variation is impossible.
6. **Imagery**: `placeholder` = fixed client enum (22 cases, `RemoteMessageModel.swift:380-403`; `iOS/DuckDuckGo/UI/RemoteMessage.xcassets`) — release-bound; remote `imageUrl` exists for medium/big*/promo/cardsList (not `small`) with 1 MB/5 MB URLCache, prefetch, load pixels (`RemoteMessagingImageProvider.swift:29-47`, `RemoteMessagingService.swift:140-147`).
7. **Repo/schema hygiene**: no android/windows schemas; CI validates ajv schema only (`.github/scripts/validate-config.sh`); template↔surface compatibility enforced client-side by silent drop.
8. **Semantics quirks**: dismissal forever (no re-show/renewal); `interactedWithMessage` = dismissed-for-any-reason (no per-action outcomes); modal messages burn on first present (shown+dismissed together); after-idle trigger iOS-only in practice.

### 7. Render paths (file:line)

**iOS NTP card**: `NewTabPageViewController.swift:71,129` → `NewTabPageMessagesModel.refresh()` → `HomePageConfiguration.homeMessages` (`iOS/DuckDuckGo/HomePageConfiguration.swift:56-82`; fetch `surfaces: .newTabPage`, after-idle preferred :73-77) → `HomeMessageViewModelBuilder.build` (`HomeMessageViewModelBuilder.swift:35-88`; cardsList → nil :145-146) → SwiftUI `HomeMessageView` in NTP (`NewTabPageView.swift:232`; `HomeMessageView.swift:28-80`). Live updates via `remoteMessagesDidChange` (`NewTabPageMessagesModel.swift:57-66`); dismissal/pixels :107-160.

**iOS modal (What's New / cards_list)**: provider registered `displayContext: .scheduled` (`PromoCoordinationFactory.swift`); loop `ModalPromptCoordinationManager.swift`; entry `Foreground.swift`. `WhatsNewCoordinator.provideModalPrompt` (`WhatsNewModalPromptProvider.swift`) → `store.fetchScheduledRemoteMessage(surfaces: .modal)` (`WhatsNewRepository.swift`) → `WhatsNewViewController` + `CardsListDisplayModel` (`WhatsNewDisplayModelMapper.swift`; `iOS/DuckDuckGo/UI/CardsListView.swift`) → pageSheet/formSheet. `didPresentModal` → shown **and** dismissed (`WhatsNewRepository.swift`). Settings replay uses persisted copy (`MainViewController+Segues.swift`). Actions use the shared `RemoteMessagingActionHandler`.

**macOS NTP (HTML)**: `ActiveRemoteMessageModel` fetches `[.newTabPage, .tabBar]` (`ActiveRemoteMessageModel.swift:219-222`), routes per surface (:128-144); `ActiveRemoteMessageModel+NewTabPage.swift:25-76` → `NewTabPageRMFClient` (`NewTabPageActionsManagerExtension.swift:220`) over `rmf_getData`/`rmf_onDataUpdate`/`rmf_dismiss`/`rmf_primaryAction`/`rmf_secondaryAction` (`macOS/LocalPackages/NewTabPage/Sources/NewTabPage/RMF/NewTabPageRMFClient.swift:46-134`); JS payload supports small/medium/bigSingleAction/bigTwoAction only (`NewTabPageDataModel+RMF.swift:41-48`).

**macOS tab bar**: `TabBarActiveRemoteMessage` → `TabBarRemoteMessageViewModel` (survey-only :64-90) → `TabBarRemoteMessageView`. **macOS promo-queue integration**: `ExternalPromo`s `remote-message-ntp`/`remote-message-tabbar` (`PromoServiceFactory+RemoteMessage.swift:24-46`).

**Pixels** (suppressible per message via `metrics.state`): shown/shown-unique/dismissed/action/primary/secondary (`HomePageConfiguration.swift:99-123`, `ActiveRemoteMessageModel.swift:166-213`); modal adds sheet/card-shown/card-clicked/image-load (`iOS/DuckDuckGo/Pixels/RemoteMessagingPixelReporter.swift:32-43`).

---

## Part 2 — iOS Promo Inventory (code-verified)

Paths below are relative to `/Users/bkunat/Desktop/ddg-workspace/apple-browsers` unless noted. Scope: proactive nudges/asks/ads. Excluded: core first-run onboarding (linear + contextual Dax dialogs, Duck.ai fire onboarding in `iOS/DuckDuckGo/MainViewController+DuckAIFireOnboarding.swift`) and OS permission dialogs.

### 0. Existing coordination infrastructure (context)

**A. ModalPromptCoordination (launch/foreground modal queue).** One modal max per evaluation, first-eligible-wins by priority, global cooldown.
- Priority order (`iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`): 1 WinBack → 2 SubscriptionPromo (reinstaller) → 3 SubscriptionPromo (existing user) → 4 AddressBarPicker → 5 DefaultBrowser → 6 What's New → 7 CookiePopupOptIn.
- Entry gates: launch source `.standard`, onboarding seen, no modal already presented (`:101-117`). Evaluated on every foreground once interaction-ready (`iOS/DuckDuckGo/AppLifecycle/AppStates/Foreground.swift:137-146`).
- Global cooldown: default 24h, remote-tunable via privacy-config `iOSBrowserConfig.promptCooldownInterval` (`iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromptCooldownIntervalProvider.swift:29-62`); last-shown key `com.duckduckgo.prompts.lastPromptShownTimestamp` (`.../Cooldown/PromptCooldownStore.swift:33-35`).
- Cross-surface courtesy signal: `RecentModalPromptStatusProviding.wasModalPromptRecentlyPresented` (implemented by `PromoCoordinationService`) is consumed by the Duck.ai sync promo.

**B. RMF on iOS.** Exactly two surfaces: NTP card (small/medium/bigSingleAction/bigTwoAction/promoSingleAction) and modal (`cardsList` = What's New) — `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-31`; NTP builder rejects `cardsList` (`HomeMessageViewModelBuilder.swift:145-146`). Actions: share/url/urlInContext/survey/appStore/dismiss/navigation(9 targets) (`SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:356-378`). **No action can write an arbitrary client setting.** Matching attributes incl. local-state bridges (bookmarks/favorites counts, widgetAdded, syncEnabled, duckPlayer*, `WinBackOfferUrgency`, `ntpAfterIdleState`, shown/dismissed ids…) populated in `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:78-199`. `afterIdle` display trigger for NTP (`HomePageConfiguration.swift:71-82`).

### 1. Launch-modal queue promos (coordinated via ModalPromptCoordination)

**1.1 Win-back offer modal (priority 1)** — discounted-resubscribe page sheet for churned Privacy Pro subscribers (`iOS/DuckDuckGo/WinBackOffer/WinBackOfferPresenter.swift:55`). Eligibility: flag on, never presented, no active subscription, churn ≥3 days, not redeemed (`SharedPackages/BrowserServicesKit/Sources/Subscription/WinBackOffer/WinBackOfferVisibilityManager.swift:111-122`); offer window 5 days from first presentation, re-offer cooldown 270 days (`:52-57`); redemption auto-detected (`:189-220`). Config: `PrivacyProSubfeature.winBackOffer` (`iOS/Core/FeatureFlag.swift:655-656`); copy hardcoded. State: keychain (`offerPresentationDate`, `churnDate`, `offerRedemption`) + KV `didDismissUrgencyMessage` (`WinbackOfferStore.swift:72-123`). Provider `iOS/DuckDuckGo/ModalPromptCoordination/Providers/WinBackOfferModalPromptProvider.swift:31-45`. **Companion: win-back urgency message is already an RMF message** matched via `WinBackOfferUrgencyMatchingAttribute` fed from the same visibility manager (`RemoteMessagingConfigMatcherProvider.swift:118,199`; `WinBackOfferVisibilityManager.swift:96-109` — last 2 days of window). Plus win-back settings rows (§5.3).

**1.2 Subscription promo (reinstallers/skipped onboarding) (priority 2)** — Privacy Pro page sheet (`SubscriptionPromoPresenter.swift:58`). Eligibility (`SubscriptionPromoCoordinator.swift:69-81,125-133`): not shown before, flags `subscriptionPromoForReinstallers` + `privacyProOnboardingPromotion` (`FeatureFlag.swift:611-614`), ATB variant == `returning_user`, `hasSkippedOnboarding`, ≥7 days since install. State: `DaxDialogsSettings.subscriptionPromotionDialogShown` (`DaxDialogsSettings.swift:108`).

**1.3 Subscription promo (existing users) (priority 3)** — the same Privacy Pro sheet for users who did not skip onboarding and have not seen an offer. Eligibility (`SubscriptionPromoExistingUserCoordinator.swift`): `subscriptionPromoForExistingUsers` + `privacyProOnboardingPromotion`, install age ≥7 days, no active contextual onboarding dialog, and no earlier subscription-promo presentation. State shares `DaxDialogsSettings.subscriptionPromotionDialogShown`; the provider uses the common prepared-prompt revalidation path.

**1.4 New address bar picker (priority 4)** — one-time non-dismissible Search-vs-Duck.ai choice sheet (`NewAddressBarPickerModalPromptProvider.swift:45-75`). Eligibility (`NewAddressBarPickerDisplayValidator.swift:69-144`): Duck.ai enabled, flag `showAIChatAddressBarChoiceScreen` (`FeatureFlag.swift:649-650`), ≥1 day since install, AIChat search-input state checks, not shown. State: app-group UserDefaults `aichat.storage.newAddressBarPickerShown.v2` (`:159-182`).

**1.5 Set-default-browser prompts (priority 5)** — active-user custom-detent sheet + inactive-user `overFullScreen` comparison modal (`iOS/LocalPackages/SetDefaultBrowser/Sources/SetDefaultBrowserUI/DefaultBrowserPromptPresenter.swift:41-104`). Gates: not permanently dismissed + live `isDefaultBrowser` false (`.../PromptDecider/DefaultBrowserPromptTypeDecider.swift:138-186`); inactive: never shown + ≥28d install + ≥7 inactive days; active: 1d post-install, again at 4 active days, then every 14 active days. **All day-counts remote-tunable** via privacy-config `setAsDefaultAndAddToDock` settings (`DefaultBrowserPromptFeatureFlagAdapter.swift:35-37`; defaults `DefaultBrowserPromptFeatureFlagger.swift:40-48`). State: KeyValueFilesStore keys `com.duckduckgo.defaultBrowserPrompt.*`. CTA uses PiP system-settings tutorial (`DefaultBrowserPromptService.swift:84-90`).

**1.6 What's New modal (priority 6) — RMF `.modal`** — remote cards modal, targeting entirely RMF (`WhatsNewModalPromptProvider.swift:71-110,171-208`; `WhatsNewRepository.swift:56-61`); on-demand replay from Settings behind `showWhatsNewPromptOnDemand` (`FeatureFlag.swift:723-724`; `SettingsOthersView.swift:35-42`).

**1.7 Cookie Pop-up Protection opt-in (priority 7)** — non-dismissible two-option consent sheet (`CookiePopupProtectionOptInModalPromptProvider.swift:157-175`). Eligibility (`:144-153`): flags `cookiePopupPreferenceSetting`+`cookiePopupOptInDialog` (`FeatureFlag.swift:571-574`), preference != `.max`, not confirmed, shown <3 times, ≥2 days since install. State: `com.duckduckgo.cookiePopupProtection.optIn.{shownCount,firstShownDate,hasConfirmed}` (`:30-32`). Confirm writes `AppUserDefaults().cookiePopupPreference` (`:180-185`).

### 2. RMF NTP card

`HomePageConfiguration.buildHomeMessages` → `fetchScheduledRemoteMessage(surfaces: .newTabPage, triggerFilter:)` incl. afterIdle (`HomePageConfiguration.swift:56-82`) → `NewTabPageMessagesModel` (`:24-92`) → `HomeMessageView` in `NewTabPageView.swift:230-233`. Suppressed while onboarding (`HomePageConfiguration.swift:59-61`). `HomeMessage` has only `.placeholder`/`.remoteMessage` — no legacy client NTP cards (`HomeMessage.swift:23-26`; `HomeMessageStorage.swift:30-33`). Impression pixels `HomePageConfiguration.swift:99-123`.

### 3. In-context feature promos (standalone — neither queue nor RMF)

**3.1 Sync promo — 4 touchpoints, one manager** (`iOS/DuckDuckGo/SyncPromoManager.swift`; touchpoints `:49-54`; eligibility `:100-139`; shared `SyncPromoView`):
- Bookmarks header card (`BookmarksViewController.swift:943-988`): flags `.syncPromotionBookmarks`+`.sync`, sync inactive, not dismissed, bookmarks >0; key `com.duckduckgo.app.sync.PromoBookmarksDismissed` (`UserDefaultsPropertyWrapper.swift:108`).
- Passwords list header card (`AutofillLoginListViewModel.swift:328-336`): flag `.syncPromotionPasswords`; key `…PromoPasswordsDismissed`.
- Data-import summary card (`DataImportSummaryViewModel.swift:94-121`): flag `.dataImportSummarySyncPromotion`; key `…PromoDataImportDismissed`.
- **Duck.ai switch-bar card** (`AIChatSyncPromoView`, `UnifiedInputContentContainerViewController.swift:869-905`): sync inactive, flags `.sync`+`.aiChatSync`+`.aiChatSyncPromo`, privacy-config `duckAiChatHistory`, not dismissed, **impression cap 3**, defers if a launch modal was just shown (`AIChatSyncPromoViewModel.swift:49-53`). State keys `sync-promo-ai-chat-{dismissed,impressions}` (`SyncPromoManager.swift:37-45,91`).

**3.2 Passwords import promo (passwords-list header, top of chain)** — gate: iOS ≥18.2, <25 credentials, `!hasImportedLogins`, flag `canPromoteImportPasswordsInPasswordManagement`, not permanently dismissed (`AutofillCredentialsImportPresentationManager.swift:93-141`; call `AutofillLoginListViewModel.swift:356-364`). State `com.duckduckgo.logins.*` (`AutofillLoginImportState.swift:26-31`). **Header priority chain (import > survey > sync > extension, one per session): `AutofillLoginListViewController.swift:747-795`.**

**3.3 Passwords import prompt (in-browser bottom sheet)** — autofill no-credentials callback per navigation, per-domain dedupe (`TabViewController.swift:4432-4479`); cap **5 presentations** + never-for-site + permanent dismissal (`AutofillCredentialsImportPresentationManager.swift:108-128`); flag `canPromoteImportPasswordsInBrowser`.

**3.4 Autofill credential-provider extension promos** (`AutofillExtensionPromotionManager.swift`; iOS ≥18; extension currently disabled `:119-158`): passwords-header card (flag `canPromoteAutofillExtensionInPasswordManagement`; **remote-tunable** `daysSinceInstalled` default 7, `minNumberPasswords` default 4 `:44-48,273-309`) + in-browser bottom sheet after login detection (`TabViewController.swift:2431-2435,4482-4511`; cap 5).

**3.5 Email Protection in-context signup** — bottom sheet on email-field focus in signup forms (JS autofill → `MainViewController+Email.swift:104-133`); flag `.incontextSignup` + English locale (`AutofillContentScopeFeatureToggles.swift:33`); permanent-dismiss key round-tripped into content-scope JS (`EmailSignupPromptViewController.swift:29`).

**3.6 Autofill survey (passwords-list header, 2nd in chain)** — English locale, privacy-config `.autofillSurveys`, first uncompleted survey from the subfeature's **remote settings list** (`AutofillSurveyManager.swift:52-78`; URL enriched `:84-127`) — remote surveys WITHOUT RMF. State `com.duckduckgo.app.autofill.SurveysCompleted`.

### 4. Engagement nudges, badges, tips (standalone)

**4.1 Home-row ("Add to Home Screen") reminder** — drop-down banner; not shown before + ≥3 days since first access (`HomeRowReminder.swift:30-72`); suppressed if user saw onboarding Add-to-Dock — effectively iPad-only (`MainViewController.swift:2906-2921`). **Fully hardcoded, no flag.** Keys `com.duckduckgo.homerow.reminder.*`.

**4.2 App rating prompt** — `SKStoreReviewController` on SERP load when `shouldPrompt()` (`TabViewController.swift:1959-1966`); 3 unique usage days (first) / 4 more (second), max twice ever (`AppRatingPrompt.swift:52-80`); flag `iOSBrowserConfigSubfeature.appRatingPrompt`. State: **Core Data** (`AppRatingPrompt.swift:85-165`).

**4.3 Duck Player native-UI pills + toast** — welcome/entry/re-entry pills on YouTube watch pages (`NativeDuckPlayerNavigationHandler.swift:252-264`; `DuckPlayerNativeUIPresenter.swift:540-556`), settings toast after exactly 3 pill dismissals (`:658-666`). Keys `com.duckduckgo.ios.duckPlayer*` (`AppUserDefaults.swift:121-124`). A full-screen `DuckPlayerPrimingModalView` exists but is **not wired** (`DuckPlayerNativeUIPresenter.swift:71-76`).

**4.4 VPN menu-row promo dot (browsing menu)** — dot + purchase routing for non-subscribers; flag `.vpnMenuItem` + view cap (`TabViewControllerMenuBuilderExtension.swift:917-961`; `VPNSubscriptionPromotionHelper.swift:96-120`; count via `FreeTrialBadgePersistor`, prefix `vpn-menu-item` `:85`). Only promo dot in the menu; generic `showNotificationDot`/`detailBadge` plumbing exists (`BrowsingMenuViewController.swift:33`) but unused elsewhere.

**4.5 VPN TipKit tips** — `VPNAddWidgetTip` (`VPNAddWidgetTip.swift:25-83`), `VPNSnoozeTip`, `VPNGeoswitchingTip`; TipKit rules on VPN runtime state; TipKit's own store.

### 5. Settings promo rows (persistent, standalone)

5.1 "Next Steps" section — Add to Dock / Add Widget / address-bar position / voice search, hardcoded, always visible, no dismissal (`SettingsNextStepsView.swift:29-59`; mounted `SettingsRootView.swift:81`). · 5.2 Privacy Pro purchase rows (`SettingsSubscriptionView.swift:127-171,416-478`). · 5.3 Win-back settings rows (`:88-125,271-299`; `SettingsViewModel.swift:1728`). · 5.4 Freemium PIR entry point (`:173-202`). · 5.5 What's New row (§1.6).

### 6. Dormant / remnants (verify before migrating)

- **Fire-mode promotions** (`iOS/DuckDuckGo/FireMode/FireModePromotionsCoordinator.swift`): NTP card, menu promotion, tab-switcher TipKit tip all hardcoded ineligible (`:121-123,146-148,166-168`); coordinator not instantiated; storage keys `fire-promotion-*` retained (`:26-36`). Matches Asana "[iOS] Remove Fire Tabs promos" (completed Jul 3, 2026).
- Duck Player priming modal — built, never presented (§4.3).
- Mac/desktop-app promo — no client promo remains; `DesktopDownloadView` only inside transactional flows; desktop promos ship via RMF NTP messages now.
- VPN waitlist — dead (`iOS/LocalPackages/Waitlist-iOS` unused).

### 7. Boundary cases (excluded from classification)

Crash-report opt-in (`CrashCollectionOnboarding.swift:55-112`), sync favicons-fetching opt-in (`FaviconsFetcherOnboarding.swift:39-70`), Duck.ai gated-model upsell (reactive, `DuckAISubscriptionUpsellPresenter.swift:58-92`), onboarding-embedded Privacy Pro promo, fireproofing alert — transactional/reactive or onboarding-embedded.

### 8. macOS comparison — `PromoServiceFactory` registrations

Registered in priority order (`macOS/DuckDuckGo/Promotions/PromoServiceFactory.swift:60-79`; kind semantics `.../PromoTypes/Promo.swift:61-102` — External = feature drives own visibility, "use sparingly"):

| id | kind | context |
|---|---|---|
| `session-restore` | External | global |
| `remote-message-ntp` (RMF) | External | newTabPage |
| `freemium-dbp-ntp-banner` | Internal | newTabPage |
| `remote-message-tabbar` (RMF) | External | global |
| `next-steps-cards` | External | newTabPage |
| `subscription-promo-fire-window` | External | fireWindow |
| `default-browser-and-dock-popover` | Internal | global |
| `default-browser-and-dock-banner` | Internal | global |
| `default-browser-and-dock-inactive-modal` | Internal | global |
| `cookie-popup-protection-opt-in` | Internal | global |
| `test-promo-a…d` | Internal | debug/review only |

Notable vs iOS: macOS funnels RMF itself and non-modal surfaces (banners, popovers, NTP cards, fire-window) through one queue; iOS's queue covers launch modals only.

### 9. Preliminary 3-way classification (hypothesis for iteration-2 RQ3 — verify)

**(a) RMF-migratable today:** What's New modal (already RMF) · NTP remote card (already RMF) · **win-back urgency message (already RMF via a local-state-bridging attribute — the proven pattern)** · autofill survey *content* (remote survey id/URL + RMF `survey` action exist; only the passwords-header placement is missing).

**(b) Blocked on a named missing RMF capability:**
- Subscription promo (reinstallers): no hero-promo modal template (modal = cardsList only); no `hasSkippedOnboarding` attribute (ATB variant + days-since-install exist).
- Cookie pop-up opt-in: no action that writes a client setting (`cookiePopupPreference = .max`); no two-option consent template; no current-preference attribute.
- Sync promos (4 touchpoints): no embedded surface (list headers / switch-bar chrome); no passwords-count attribute; no per-message impression caps (Duck.ai variant caps at 3).
- Passwords import header promo: missing header surface + credential-count (<25) + `hasImportedLogins` attributes.
- Autofill extension header promo: missing header surface + extension-enabled attribute + remote thresholds.
- VPN menu dot: no menu-badge/dot surface; no view-count capping.
- Home-row reminder: no in-app banner/toast surface; needs "saw add-to-dock in onboarding" attribute.
- Fire-mode NTP promo (if revived): fits NTP templates but no open-fire-mode action, no `hasBurnedTabs`/`hasVisitedFireMode` attributes (cf. Android added exactly these).

**(c) Should likely stay client-side:** win-back launch modal (transactional offer state machine + StoreKit; RMF consumes its state instead) · address bar picker (writes settings, forced choice) · default-browser prompts (live `isDefaultBrowser` check, activity ledger, PiP tutorial; scheduling already remote-tunable) · in-browser import/extension prompts + email in-context signup (real-time page events, per-domain state) · app rating (StoreKit-mediated) · Duck Player pills/toast (per-video, navigation-timed) · VPN TipKit tips · settings promo rows (persistent navigation UI).

**Cross-cutting:** iteration 1 coordinates the seven launch modals against visible NTP RMF when its flag is enabled; the broader promo inventory remains outside that seam except for two ad-hoc links — the Duck.ai sync promo checking `wasModalPromptRecentlyPresented`, and the passwords-list header's private 4-way priority chain (`AutofillLoginListViewController.swift:747-795`). Those remain natural candidates for a future central promo service.

---

## Corrections to the appendix (re-verified Jul 10, 2026)

These corrections were found while producing `iteration_2_findings.md`; the generated body above is intentionally left unchanged.

1. **RMF does have experiment-variant targeting.** The “no experiments/cohorts” wording in Part 1 §2/§6 is too broad: `expVariant` is parsed and compared with `VariantManager.currentVariant`. Only privacy-config cohort flags are excluded from `allFeatureFlagsEnabled`. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:24-34,70-81`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/AppAttributeMatcher.swift:111-130`; `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:165-167`.
2. **Modal coordination does not enforce a separate one-modal-per-session gate.** `didPresentModalPromptThisSession` is a courtesy signal consumed by the Duck.ai Sync promo; repeat presentation is prevented by the remote-tunable global cooldown (default 24 hours). `iOS/DuckDuckGo/ModalPromptCoordination/ModalPromptCoordinationManager.swift`; `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`; `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromptCooldownIntervalProvider.swift`.
3. **Autofill Survey is class (b) as a complete promo, not class (a).** RMF can carry its survey content/action, but not the passwords-list header; the RMF survey whitelist also lacks the current `saved_passwords` parameter. `iOS/DuckDuckGo/AutofillSurveyManager.swift:84-125`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/RemoteMessagingSurveyActionMapping.swift:21-39`; `iOS/DuckDuckGo/AutofillLoginListViewController.swift:760-765`.
4. **Active inventory omissions:** add the VPN expired-entitlement alert (`iOS/DuckDuckGo/AppServices/VPNService.swift:59-100`), Settings Complete Setup (`iOS/DuckDuckGo/SettingsCompleteSetupView.swift:24-81`), active Return-to-Tab utility (`iOS/DuckDuckGo/AppLifecycle/IdleReturnEligibilityManager.swift:25-47,95-116`), Duck Player's user-invoked feature explainer (`iOS/DuckDuckGo/DuckPlayer/Modal/DuckPlayerModalPresenter.swift:24-47`), PIR `NEW` badge (`iOS/DuckDuckGo/NewBadge/NewBadgeVisibilityManager.swift:25-50,78-101`), VPN TipKit tips (`iOS/DuckDuckGo/VPNTipsModel.swift:29-80,98-126`), and inactivity notification (`iOS/DuckDuckGo/AppServices/InactivityNotificationSchedulerService.swift:25-34,58-82,99-140`).
5. **Fire-mode promo remnants are not built.** In addition to hardcoded `false` eligibility, `FireModePromotionsCoordinator.swift` is absent from the Xcode project and references the removed `FireTabsTip`; classify the three old surfaces as removed/non-built, not merely dormant. `iOS/DuckDuckGo/FireMode/FireModePromotionsCoordinator.swift:120-180`; `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` (no file reference).
6. **Duck Player distinction:** native welcome/entry/re-entry pills, toast, and the separate feature-explainer are active; only `DuckPlayerPrimingModalView` is unreferenced. `iOS/DuckDuckGo/DuckPlayer/NativeUI/DuckPlayerNativeUIPresenter.swift:517-555,642-666`; `iOS/DuckDuckGo/DuckPlayer/DuckPlayer.swift:695-720`.
7. **Settings/product-name corrections:** Next Steps is always mounted and Complete Setup contains Default Browser + generic Import Passwords; there is no implemented 14-day Next Steps hide. The product's Identity Theft/PIR label maps to a PIR `NEW` badge with 7-day/3-minor-release expiry; the active VPN menu treatment is a capped dot, not a pill. `iOS/DuckDuckGo/SettingsNextStepsView.swift:25-58`; `iOS/DuckDuckGo/SettingsCompleteSetupView.swift:24-81`; `iOS/DuckDuckGo/NewBadge/NewBadgeVisibilityManager.swift:25-50`; `iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift:917-960`.
8. **A new surface does not automatically require a Core Data migration.** Surfaces are an `Int16` OptionSet already persisted as a numeric bitmask; the required work is a schema/JSON enum, new bit, platform allowlist, renderer/consumer, queue bridge, pixels, and tests. A data-model migration is needed only if the storage representation itself changes. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:193-210`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:217-229,443-459`.
9. **Live-config count wording:** iOS v114 contains 24 message objects but only 10 distinct IDs; the two survey IDs are repeated eight times each. `remote-messaging-config/live/ios-config/ios-config.json#/messages`.
10. **Android action-name note:** the checked-in generic/Android-oriented templates use JSON values such as `defaultBrowser`, `playstore`, `url`, and `dismiss`; the appendix's `default_browser`/`website`/`search` vocabulary is not supported by these checkouts. Android client behavior remains unverified because its source is not present. `remote-messaging-config/templates/messages/content/action/`.
11. **Iteration-1 architecture changed after deeper integration review.** Iteration 1 no longer extracts macOS `PromoService` or creates `SharedPackages/PromoQueue`. The baseline is the existing iOS modal coordination plus a small app-level cross-surface permit coordinator: `Foreground`/`UIInteractionManager` retain lifecycle readiness; the service retains onboarding, launch-source, and unrelated-modal gates; the manager retains provider priority, cooldown, and presentation while holding the mutual-exclusion lease until a checkpoint confirms the presented modal root is gone (providers gain no dismissal signal; see `TECH_DESIGN_FINAL.md`); NTP reports actual per-instance RMF visibility and is render-gated. An RMF that appears after modal commit waits without shown/dismissed accounting; the modal is never retracted programmatically. `PromoService` remains an iteration-3 candidate/comparison, not shipped iOS infrastructure.
