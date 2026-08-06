# Iteration 2 findings — which iOS promos can move to RMF

**Decision pre-read · verified 10 July 2026**

**Apple checkout:** `c48ee2b6cf` on `bartosz/promo-queue`

**RMF config checkout:** `9ab24a7` on `bartosz/promo-queue`

This report answers iteration-2 RQ1–RQ5. It starts from `iteration_2_research_appendix.md`, re-opens every load-bearing citation in the current checkouts, reconciles the 74 names in the product inventory, and classifies the resulting canonical promo units.

> **Source rule.** Statements attributed to product/stakeholder discussions are **reported (Asana), not code-verifiable** and cite the local digest. Code and config claims cite the current checkout. Negative inventory findings were checked with case-insensitive `rg` searches across `iOS/**/*.swift`, `iOS/**/*.strings`, `iOS/**/*.pbxproj`, `SharedPackages/**/*.swift`, and the four live RMF JSON files.

## 0. Decision summary and headline corrections

### Bottom line

1. **RMF is ready today only where the end-to-end path already exists.** On iOS that means banner content on the NTP and `cards_list` content presented by the native What's New modal. The NTP channel, win-back urgency, and What's New infrastructure are already RMF-backed; nothing live in the iOS config currently uses the modal path. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:23-32`; `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:56-75`; `remote-messaging-config/live/ios-config/ios-config.json:5-860`
2. **The real migration blocker is surfaces, not Settings navigation.** `navigation: sync` already calls the Sync settings segue. Pablo's contrary claim is **reported (Asana), contradicted by code**; Cristian's correction is confirmed. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:356-377`; `iOS/DuckDuckGo/MessageNavigator.swift:50-72`; reported discussion: `promo-queue-docs/iteration_2_research.md:31-35`
3. **Twelve active promo units are reasonable RMF candidates but blocked.** All 12 need a native-surface/RMF bridge or a new renderer; eight additionally need a local-state attribute, three need cap semantics, and two have event-latency constraints. Two also lack actions needed for a hypothetical first-class RMF renderer, but those actions are **not required by the proposed hybrid migrations**, which keep consent/system action handling local. Counts are non-additive and use the canonical rows in §B.3.
4. **The highest-value first build is a hybrid native-surface contract, then the seven active header/card promos.** RMF supplies remote scheduling/content/kill; the existing native view supplies rendering and immediate local eligibility; a future common arbitration contract decides visibility. Iteration 1 provides only a narrow NTP/modal permit precedent, not a general client queue. The Android Fire Mode precedent for the hybrid pattern is **reported (Asana), not code-verifiable in these repos**. `promo-queue-docs/iteration_2_research.md:73-83`
5. **Migration does not solve client-side arbitration.** RMF has one scheduled winner globally, config-order priority, and no impression caps, re-show cooldowns, cross-message pacing, severity, or context model. Iteration 3 must still choose RMF, client, or hybrid ownership beyond the targeted iteration-1 seam. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:51-78`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:92-125,443-506`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/CoreData/RemoteMessaging.xcdatamodeld/RemoteMessaging 3.xcdatamodel/contents:3-14`

### Corrections found during verification

- **The appendix and iteration-3 hard fact “no experiments/cohorts” is too broad.** RMF supports `expVariant` against `VariantManager.currentVariant`; only privacy-config cohort flags are excluded from `allFeatureFlagsEnabled`. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:24-34,70-81`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/AppAttributeMatcher.swift:111-130`; `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:165-167`
- **The appendix's “one modal/session” description is not a rule.** `didPresentModalPromptThisSession` is written and exposed as a courtesy signal, but it is never an eligibility gate. The remote-tunable global cooldown, default 24 hours, is the actual repeat-prevention mechanism. `iOS/DuckDuckGo/ModalPromptCoordination/ModalPromptCoordinationManager.swift`; `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`; `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromptCooldownIntervalProvider.swift`
- **Autofill Survey is class (b), not (a), as a whole promo.** Its remote content and survey action fit RMF, but the passwords-header surface and `saved_passwords` query parameter do not. `iOS/DuckDuckGo/AutofillSurveyManager.swift:84-125`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/RemoteMessagingSurveyActionMapping.swift:21-39`; `iOS/DuckDuckGo/AutofillLoginListViewController.swift:760-765`
- **There is no generic iOS “zero extra queue work” path.** Iteration 1 render-gates NTP RMF only. Every new modal, badge, header, or tab-switcher surface needs its own visibility, accounting, and arbitration integration. macOS's separate observation-only ExternalPromos remain comparison evidence, not the iOS baseline. `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+RemoteMessage.swift:24-46`; `macOS/DuckDuckGo/RemoteMessaging/RemoteMessagePromoDelegate.swift:23-80`
- **The generated inventory omitted active units:** VPN expired-entitlement alert, Settings Complete Setup, Return-to-Tab, Duck Player's user-invoked explainer, the PIR `NEW` badge, VPN TipKit tips, and an inactivity notification; it also overstated the Fire remnants as merely dormant. Evidence and final dispositions are in §B and the corrections are appended to the appendix.

---

## A. RQ1 — RMF capability map, verified in code

### A.1 Platform capability matrix

Legend: **✓ supported end-to-end**, **~ partial/restricted**, **✗ missing**, **? client not present in these checkouts**.

| Capability | iOS | macOS | Android | Windows |
|---|---|---|---|---|
| `small` / `medium` / `big_single_action` / `big_two_action` banners | ✓ NTP. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-30`; `iOS/DuckDuckGo/HomeMessageViewModelBuilder.swift:110-147` | ✓ NTP; ~ tab bar is narrower. `macOS/DuckDuckGo/RemoteMessaging/DefaultRemoteMessagingSurfacesProvider.swift:22-31`; `macOS/DuckDuckGo/TabBar/ViewModel/TabBarRemoteMessageViewModel.swift:63-93` | ? Live config proves `big_single_action`, not renderer behavior. `remote-messaging-config/live/android-config/android-config.json#/messages` | ? Live config proves `medium`/`big_single_action`, not renderer behavior. `remote-messaging-config/live/windows-config/windows-config.json#/messages` |
| `promo_single_action` | ✓ NTP. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-30` | ✗ explicitly unsupported. `macOS/DuckDuckGo/RemoteMessaging/ActiveRemoteMessageModel.swift:227-237` | ? No schema/client here | ? No schema/client here |
| `cards_list` | ✓ only through What's New `.modal`. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-31`; `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:56-75` | ✗ effective: declared `.dedicatedTab`, but the consumer fetches only NTP/tab bar. `macOS/DuckDuckGo/RemoteMessaging/DefaultRemoteMessagingSurfacesProvider.swift:22-31`; `macOS/DuckDuckGo/RemoteMessaging/ActiveRemoteMessageModel.swift:219-222` | ? | ? |
| NTP surface | ✓ five banner templates. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-30` | ✓ four effective banner templates. `macOS/LocalPackages/NewTabPage/Sources/NewTabPage/RMF/NewTabPageDataModel+RMF.swift:32-73` | ? | ? |
| Modal / sheet | ~ `cards_list`/What's New only; not a generic hero/consent sheet. `iOS/DuckDuckGo/ModalPromptCoordination/Providers/WhatsNewModalPromptProvider.swift:71-110,171-208` | ✗ effective | ? | ? |
| Dedicated tab / tab bar | ✗. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-31` | ~ tab bar only accepts a survey `bigSingleAction`; dedicated tab is unconsumed. `macOS/DuckDuckGo/TabBar/ViewModel/TabBarRemoteMessageViewModel.swift:63-93`; `macOS/DuckDuckGo/RemoteMessaging/ActiveRemoteMessageModel.swift:219-222` | ? | ? |
| Remote images | ✓ all types except `small`; cached and prefetched. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:212-242`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingImageProvider.swift:27-61`; `iOS/DuckDuckGo/AppServices/RemoteMessagingService.swift:133-147` | ~ model accepts URL, NTP renderer ignores it. `macOS/LocalPackages/NewTabPage/Sources/NewTabPage/RMF/NewTabPageDataModel+RMF.swift:57-71` | ? | ? |
| In-app navigation | ✓ eight useful targets; `softwareUpdate` is a no-op. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:356-377`; `iOS/DuckDuckGo/MessageNavigator.swift:50-72` | ~ smaller effective set. `macOS/DuckDuckGo/NewTabPage/Features/ActiveRemoteMessageModel+NewTabPage.swift:56-66` | ? Config templates expose different names | ? |
| Multi-message / per-surface scheduling | ✗ one scheduled winner globally. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:92-125,443-506` | ✗ shared store | ? | ? |
| Priority / severity / context | ~ JSON order is priority; no fields for severity/context. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:51-78`; `remote-messaging-config/schemas/ios/schema.json#/properties/messages` | ~ shared engine | ? | ? |
| Impression cap / re-show cooldown / global pacing | ✗. Persisted state has shown/date/status only. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/CoreData/RemoteMessaging.xcdatamodeld/RemoteMessaging 3.xcdatamodel/contents:3-14` | ✗ shared store | ? | ? |
| Per-user expiry | ~ `dismissAfterDaysShown`; no absolute campaign dates. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:255-264` | ~ shared store | ? | ? |
| Experiments / percentile | ~ `expVariant` plus stable per-message percentile; privacy-config cohort flags are excluded. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/AppAttributeMatcher.swift:111-130`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:139-151`; `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:165-167` | ~ shared matcher | ? | ? |
| Standard pixels | ✓ shown/unique/dismiss/action/primary/secondary; modal adds card/sheet/image events. `iOS/DuckDuckGo/HomePageConfiguration.swift:99-123`; `iOS/DuckDuckGo/NewTabPageMessagesModel.swift:121-155`; `iOS/DuckDuckGo/Pixels/RemoteMessagingPixelReporter.swift:31-43,66-127` | ✓ base shown/action. `macOS/DuckDuckGo/RemoteMessaging/ActiveRemoteMessageModel.swift:166-213` | ? | ? |

Only iOS and macOS schemas exist in the config repo; Android/Windows cells therefore state live-config evidence without pretending to verify client renderers. `remote-messaging-config/schemas/ios/schema.json`; `remote-messaging-config/schemas/macos/schema.json`; `remote-messaging-config/live/android-config/android-config.json`; `remote-messaging-config/live/windows-config/windows-config.json`

### A.2 iOS matching vocabulary

The Apple mapper recognizes **44 keys**; **38 are effective on iOS**. New keys map to `UnknownMatchingAttribute` and use the rule's fallback/skip behavior, so a real new targeting dimension is release-gated. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:24-68,415-423`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:88-100`

- **31 Apple-shared:** `locale`, `osApi`, `formFactor`, `isInternalUser`, `appId`, `appVersion`, `atb`, `appAtb`, `searchAtb`, `expVariant`, `appTheme`, `bookmarks`, `favorites`, `daysSinceInstalled`, `emailEnabled`, `daysSinceNetPEnabled`, `pproEligible`, `pproSubscriber`, `pproDaysSinceSubscribed`, `pproDaysUntilExpiryOrRenewal`, `pproPurchasePlatform`, `pproSubscriptionStatus`, `pproSubscriptionTier`, `subscriptionFreeTrialActive`, `duckPlayerOnboarded`, `duckPlayerEnabled`, `interactedWithMessage`, `messageShown`, `allFeatureFlagsEnabled`, `daysSinceDuckAiUsed`, `isCurrentPIRUser`. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/AppAttributeMatcher.swift:84-130`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/UserAttributeMatcher.swift:318-396`
- **Seven iOS-only:** `widgetAdded`, `syncEnabled`, `ntpAfterIdleState`, `shouldShowWinBackOfferUrgencyMessage`, `isFreemiumPIREligible`, `freemiumPIRDidActivate`, `freemiumPIRFirstScanResult`. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/UserAttributeMatcher.swift:117-137`
- **Six macOS-only:** `installedMacAppStore`, `canUpgradeOS`, `pinnedTabs`, `customHomePage`, `isCurrentFreemiumPIRUser`, `interactedWithDeprecatedMacRemoteMessage`. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/AppAttributeMatcher.swift:32-80`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/UserAttributeMatcher.swift:213-233`

`messageShown` and `interactedWithMessage` expose shown and permanently dismissed message IDs for cross-message rules. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/UserAttributeMatcher.swift:368-383`; `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:162-207`

Schema drift is real: the iOS schema lists 41 attributes but misses `pproSubscriptionTier` and `ntpAfterIdleState`, admits macOS-only keys, and omits several modeled `cards_list` item fields. `remote-messaging-config/schemas/ios/schema.json:177-229,350-360,389-429`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/JsonRemoteMessagingConfig.swift:76-99,116-129`

### A.3 Actions, lifecycle, localization, and live config

- Actions are `share`, `url`, `url_in_context`, `appstore`, `dismiss`, `survey`, and `navigation`; iOS executes all seven. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/JsonRemoteMessagingConfig.swift:150-158`; `iOS/DuckDuckGo/RemoteMessagingActionHandling.swift:63-86`
- Navigation targets are `duckai.settings`, `settings`, `settings.general`, `feedback`, `sync`, `import.passwords`, `appearance`, `pir.main`, and `softwareUpdate`; iOS handles the first eight. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:356-377`; `iOS/DuckDuckGo/MessageNavigator.swift:50-72`
- iOS fetches on foreground, config-asset updates, and a background task with a four-hour minimum. Matching re-runs only for a new config version, explicit invalidation, or an evaluation older than 24 hours. `iOS/DuckDuckGo/AppLifecycle/AppStates/Foreground.swift:149-158`; `iOS/DuckDuckGo/AppServices/RemoteMessagingService.swift:114-147`; `iOS/DuckDuckGo/RemoteMessagingClient.swift:127-158`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigProcessor.swift:49-85`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessagingConfig.swift:24-45`
- Dismissal is permanent and invalidates the config. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:324-369`
- Localization is inline JSON with exact-locale then language fallback. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/JsonRemoteMessagingConfig.swift:29-36,116-129`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:440-455`

Current live inventory:

| Platform | Version | Message objects | Distinct IDs | Rules | Verified source |
|---|---:|---:|---:|---:|---|
| iOS | 114 | 24 | 10 | 27 | `remote-messaging-config/live/ios-config/ios-config.json#/version,#/messages,#/rules` |
| macOS | 58 | 23 | 11 | 29 | `remote-messaging-config/live/macos-config/macos-config.json#/version,#/messages,#/rules` |
| Android | 106 | 20 | 6 | 23 | `remote-messaging-config/live/android-config/android-config.json#/version,#/messages,#/rules` |
| Windows | 64 | 7 | 7 | 15 | `remote-messaging-config/live/windows-config/windows-config.json#/version,#/messages,#/rules` |

iOS's 10 IDs are two survey families repeated eight times each, one general survey, three PIR messages, win-back urgency, an after-idle NTP message, and two YouTube/ad-blocker messages. Only `medium`, `big_single_action`, and `big_two_action` are live; there is no live modal/cards-list campaign. `remote-messaging-config/live/ios-config/ios-config.json:5-860`

| Live iOS ID | Objects | Template / effective surface | Targeting gist |
|---|---:|---|---|
| `ios_privacy_pro_exit_survey_1` | 8 | `big_single_action` / NTP | Subscription platform/status/expiry, app version, locale groups. `remote-messaging-config/live/ios-config/ios-config.json:5-147,865-1107` |
| `ios_privacy_pro_subscriber_survey_1` | 8 | `big_single_action` / NTP | Active subscriber ≥30 days; excludes users who dismissed the exit survey; locale groups. `remote-messaging-config/live/ios-config/ios-config.json:151-333,1108-1278` |
| `ddg_ios_survey_1` | 1 | `big_single_action` / NTP | Days since install, `en-US`, target percentile below 0.6. `remote-messaging-config/live/ios-config/ios-config.json:337-355,918-941` |
| `ios_pir_freemium_entry_point` | 1 | `big_single_action` / NTP | Freemium-PIR eligibility/activation state; `navigation:pir.main`. `remote-messaging-config/live/ios-config/ios-config.json:358-378,1279-1300` |
| `ios_pir_freemium_scan_complete_results` | 1 | `big_single_action` / NTP | Freemium-PIR first-scan result with matches. `remote-messaging-config/live/ios-config/ios-config.json:379-399,1301-1311` |
| `ios_pir_freemium_scan_complete_no_results` | 1 | `big_single_action` / NTP | Freemium-PIR first-scan result without matches. `remote-messaging-config/live/ios-config/ios-config.json:400-419,1312-1322` |
| `ios_winback_offer_urgency` | 1 | `big_two_action` / NTP | Local `shouldShowWinBackOfferUrgencyMessage` attribute. `remote-messaging-config/live/ios-config/ios-config.json:422-443,1278-1286` |
| `ios_ntp_after_idle_existing_users_2026` | 1 | `big_two_action` / NTP, `after_idle`, dismiss after 5 days | App version/days installed and after-idle state. `remote-messaging-config/live/ios-config/ios-config.json:445-625,1323-1414` |
| `funnel_newtab_adblockermf_ios1a` | 1 | `medium` / NTP, remote image | Locale/app version/Duck Player state; sibling-message exclusion. `remote-messaging-config/live/ios-config/ios-config.json:627-744,1415-1495` |
| `funnel_newtab_adblockermf_ios2a` | 1 | `medium` / NTP, remote image | Locale/app version/Duck Player state; reciprocal sibling exclusion. `remote-messaging-config/live/ios-config/ios-config.json:745-860,1496-1505` |

---

## B. RQ2 and RQ3 — canonical iOS inventory and final classification

### B.1 Classification rule

- **(a) RMF-ready today:** the full promo works end to end on an existing iOS RMF surface with current targeting/actions.
- **(b) Blocked on a named RMF gap:** remote scheduling/content is reasonable, but a surface, action, matcher, cap, or latency requirement is missing.
- **(c) Stays client-side:** presentation is tightly coupled to live OS/page/navigation state or transactional/system UI. It should still publish visibility/request permission under whichever common arbitration model iteration 3 selects.

For gap counts, one row below equals one canonical presentation/eligibility/state machine. Product aliases in §B.6 do not create extra units. Already-RMF content such as win-back urgency is counted under the generic NTP channel, not again.

### B.2 Already RMF — class (a)

| Canonical unit | Surface, trigger/config, storage/pacing | Decision |
|---|---|---|
| RMF NTP channel, including live win-back urgency | Inline NTP banner; normal or `after_idle`; onboarding suppressed; permanent dismissal; optional relative expiry; standard RMF pixels. Win-back urgency is a live `big_two_action` message targeted by the last two days of its local five-day offer. `iOS/DuckDuckGo/HomePageConfiguration.swift:56-123`; `iOS/DuckDuckGo/NewTabPageMessagesModel.swift:107-160`; `SharedPackages/BrowserServicesKit/Sources/Subscription/WinBackOffer/WinBackOfferVisibilityManager.swift:96-109`; `remote-messaging-config/live/ios-config/ios-config.json:422-443` | **(a), already RMF.** Iteration 1 coordinates the whole NTP surface through one app-level visibility aggregate; messages are not individual modal providers. |
| What's New | Native page/form sheet consumes RMF `cards_list`, marks it shown and dismissed on presentation, and saves it for Settings replay. No live iOS campaign today. `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:42-78`; `iOS/DuckDuckGo/ModalPromptCoordination/Providers/WhatsNewModalPromptProvider.swift:71-110,171-219`; `remote-messaging-config/live/ios-config/ios-config.json:5-860` | **(a), already RMF infrastructure.** Keep it as the existing native modal provider; do not invent an `InternalPromo` wrapper for iteration 1. |

### B.3 RMF candidates blocked on named gaps — class (b)

| Canonical unit | Current behavior and guidance check | Exact RMF gap; migration/queue call |
|---|---|---|
| Subscription reinstaller / skipped-onboarding sheet | Once-only page sheet; returning variant + skipped onboarding + ≥7 days; privacy-config flags and local shown state. `iOS/DuckDuckGo/SubscriptionPromo/SubscriptionPromoCoordinator.swift:42-84,125-133`; `iOS/DuckDuckGo/SubscriptionPromo/SubscriptionPromoPresenter.swift:39-64` | **Modal/hero surface + `hasSkippedOnboarding` attribute.** Hybrid native sheet; retain the existing modal provider until iteration 3 chooses broader ownership. |
| Cookie Pop-up Protection opt-in | Native two-choice consent; <3 shows, ≥2 days, unconfirmed, preference not max; writes preference. `iOS/DuckDuckGo/ModalPromptCoordination/Providers/CookiePopupProtectionOptInModalPromptProvider.swift:28-59,88-185` | **Consent modal + preference/confirmed/count attributes + arbitrary-setting action + cap semantics.** Hybrid keeps consent/action and the existing modal provider local. |
| Sync — bookmarks header | Visible in the bookmarks list when sync is inactive, flags on, bookmarks >0, not dismissed; no cap/expiry. `iOS/DuckDuckGo/BookmarksViewController.swift:943-988`; `iOS/DuckDuckGo/SyncPromoManager.swift:102-109,141-171` | **Bookmarks-header surface.** `bookmarks`, `syncEnabled`, flags, and `navigation:sync` already exist. Strong hybrid; queue bookmarks-list context. |
| Sync — passwords header | Passwords header, >0 accounts, sync inactive, not dismissed; no cap/expiry. `iOS/DuckDuckGo/AutofillLoginListViewModel.swift:328-336`; `iOS/DuckDuckGo/SyncPromoManager.swift:110-117,141-171` | **Passwords-header surface + credential-count attribute.** Hybrid; queue shared passwords-header context. |
| Sync — data-import summary | Immediate post-import summary card; flag on, sync inactive, not dismissed; no cap/expiry. `iOS/DuckDuckGo/DataImport/DataImportSummaryViewModel.swift:84-124,139-145`; `iOS/DuckDuckGo/SyncPromoManager.swift:118-124` | **Summary surface + import-event/count attribute + event latency.** Hybrid uses local eligibility; queue summary context. |
| Sync — Duck.ai switch-bar | Duck.ai chrome card, requires active/attached UI and chats, defers after launch modal, capped at 3. `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift:867-904`; `iOS/DuckDuckGo/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoViewModel.swift:49-75`; `iOS/DuckDuckGo/SyncPromoManager.swift:125-163` | **Duck.ai-chrome surface + chat/current-UI attributes + cap + event latency.** Hybrid; queue Duck.ai context. |
| Password import — passwords header | First in private four-way header chain; iOS ≥18.2, <25 credentials, no prior import, flag on, not dismissed; no cap/expiry. `iOS/DuckDuckGo/CredentialsImport/AutofillCredentialsImportPresentationManager.swift:93-141`; `iOS/DuckDuckGo/AutofillLoginListViewController.swift:746-795` | **Passwords-header surface + credential-count + `hasImportedLogins` attributes.** `navigation:import.passwords` exists. Hybrid; keep priority 1 in shared header queue. |
| Autofill extension — passwords header | iOS ≥18, provider disabled, ≥7 days/≥4 credentials by remote thresholds, not dismissed; unlimited until dismissal. `iOS/DuckDuckGo/AutofillExtensionPromotion/AutofillExtensionPromotionManager.swift:42-53,88-149,176-235,262-309` | **Passwords-header surface + provider-enabled/credential-count attributes + extension-management action.** Hybrid avoids action gap; priority 4 in shared header queue. |
| Autofill survey — passwords header | Second in header chain; English; first uncompleted survey from privacy-config; CTA/dismiss completes ID; adds `saved_passwords`. `iOS/DuckDuckGo/AutofillSurveyManager.swift:35-78,84-125`; `iOS/DuckDuckGo/AutofillLoginListViewController.swift:760-765,1182-1215` | **Passwords-header surface + `saved_passwords` survey parameter.** Hybrid keeps URL enrichment; priority 2 in shared header queue. |
| Home-row reminder / “Add to Home Screen” | Floating notification once, >3 days after first access, only if onboarding Add-to-Dock was not seen. Hardcoded local keys; one-shot is guidance-friendly but has no remote kill. `iOS/DuckDuckGo/MainViewController.swift:2906-2920`; `iOS/DuckDuckGo/HomeRowReminder.swift:23-69,74-115` | **Floating-banner surface + onboarding-state attribute.** Hybrid; keep native presentation and expose it to the future arbiter. |
| VPN browsing-menu promo dot | Non-subscriber dot, privacy flag, cap 4, state key prefix `vpn-menu-item`. `iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift:917-960`; `iOS/DuckDuckGo/Subscription/FreeTrials/VPNSubscriptionPromotionHelper.swift:83-125`; `SharedPackages/BrowserServicesKit/Sources/Subscription/FreeTrials/FreeTrialBadgePersistor.swift:28-63` | **Menu-dot surface + cap semantics.** Hybrid; queue menu context. |
| PIR Settings `NEW` badge | Active PIR badge; expires after 7 days and within 3 minor releases. `iOS/DuckDuckGo/SettingsSubscriptionView.swift:217-227,342-370`; `iOS/DuckDuckGo/NewBadge/NewBadgeVisibilityManager.swift:25-50,78-101` | **Settings-badge surface/lifecycle.** Hybrid only if remote campaign control is valuable; persistent Settings UI otherwise remains local. |

### B.4 Stays client-side — class (c), with future arbitration disposition

| Canonical unit/family | Why it remains local | Arbitration disposition and evidence |
|---|---|---|
| Win-back launch offer | Transactional subscription/redemption state and exact local offer window; RMF already consumes the urgency attribute. `SharedPackages/BrowserServicesKit/Sources/Subscription/WinBackOffer/WinBackOfferVisibilityManager.swift:52-57,96-165,222-261` | Keep the existing provider/local state. A future queue may register it as an internal candidate; iteration 1 does not wrap it. |
| Address-bar Search vs Duck.ai picker | Forced setting choice, onboarding compatibility, current search-input states, writes app-group setting. `iOS/DuckDuckGo/AIChat/NewAddressBarPicker/NewAddressBarPickerDisplayValidator.swift:69-145,159-181`; `iOS/DuckDuckGo/AIChat/NewAddressBarPicker/NewAddressBarPickerViewModel.swift:42-46` | Keep the existing provider and privacy-config kill. A future arbiter may grant presentation permission without owning the setting mutation. |
| Default Browser active + inactive/reactivation | Live OS default-browser state, activity ledger, recurring schedule, PiP/system Settings tutorial; thresholds already remote-tunable. `iOS/LocalPackages/SetDefaultBrowser/Sources/SetDefaultBrowserCore/PromptDecider/DefaultBrowserPromptTypeDecider.swift:138-185`; `iOS/LocalPackages/SetDefaultBrowser/Sources/SetDefaultBrowserCore/FeatureFlagger/DefaultBrowserPromptFeatureFlagger.swift:27-47`; `iOS/DuckDuckGo/AppServices/DefaultBrowserPromptService.swift:59-70,84-88` | Keep both variants behind the existing provider. Review 14-active-day repeat against the reported ≥28-day guidance. Guidance is reported (Asana), not code-verifiable: `promo-queue-docs/iteration_2_research.md:51-53`. |
| VPN expired-entitlement alert | Essential transactional state, active on resume/live notification, one-shot group-default flag; can preempt current UI. `iOS/DuckDuckGo/AppServices/VPNService.swift:59-100`; `iOS/DuckDuckGo/MainViewController.swift:3284-3302` | **Observe/register only after essential-preemption semantics are decided.** Do not subject it to promotional cooldown. |
| In-browser password import sheet | Real-time Autofill/page event, per-domain/vault state, cap 5, immediate native flow. `iOS/DuckDuckGo/TabViewController.swift:4432-4479`; `iOS/DuckDuckGo/CredentialsImport/AutofillCredentialsImportPresentationManager.swift:77-128` | Keep the local event path; a future arbiter may grant permission in a web-page context. |
| In-browser Autofill extension sheet | Real-time post-login/navigation event, provider/domain state, system-management flow, cap 5. `iOS/DuckDuckGo/TabViewController.swift:2424-2440,4482-4511`; `iOS/DuckDuckGo/AutofillExtensionPromotion/AutofillExtensionPromotionManager.swift:228-259` | Keep the local event path; a future arbiter may grant permission in a web-page context. |
| Email Protection in-context signup | Content-scope/Autofill callback, signup state, English/privacy flag; permanent “don't show” round-trip. Exact DOM trigger is not in this checkout. `iOS/DuckDuckGo/MainViewController+Email.swift:104-133`; `iOS/DuckDuckGo/EmailSignupPromptViewController.swift:29-40,77-107`; `SharedPackages/BrowserServicesKit/Sources/BrowserServicesKit/Email/EmailManager.swift:483-498` | Keep the local JS-event path; a future arbiter may grant global-modal permission. |
| App rating | StoreKit system prompt on DDG SERP, first after 3 unique days then 4 more, max twice, Core Data state. `iOS/DuckDuckGo/TabViewController.swift:1959-1966`; `iOS/DuckDuckGo/AppRatingPrompt.swift:38-81,85-163` | Future presentation permission before the StoreKit request; do not remote-render. |
| Duck Player pills/toast | Live YouTube navigation and per-video entry/re-entry; toast after exactly three dismissals. `iOS/DuckDuckGo/DuckPlayer/NativeUI/NativeDuckPlayerNavigationHandler.swift:248-263`; `iOS/DuckDuckGo/DuckPlayer/NativeUI/DuckPlayerNativeUIPresenter.swift:517-555,642-666` | **Observe visibility** in web-page context; do not remote-schedule. |
| Duck Player feature explainer | User-invoked SERP/YouTube educational sheet. `iOS/DuckDuckGo/DuckPlayer/DuckPlayer.swift:695-720`; `iOS/DuckDuckGo/DuckPlayer/Modal/DuckPlayerModalPresenter.swift:24-47` | Publish user-initiated visibility only if global modal conflicts remain possible. |
| VPN TipKit tips | Live VPN state plus TipKit persistence. `iOS/DuckDuckGo/VPNTipsModel.swift:29-80,98-126`; `iOS/DuckDuckGo/NetworkProtectionStatusView.swift:150-160,469-535` | Observe/register in the owning surface; do not migrate content by default. |
| Settings Complete Setup, Next Steps, subscription/win-back rows | Persistent navigation IA with local eligibility/dismissal; Next Steps is always mounted; Complete Setup contains default browser and generic import. `iOS/DuckDuckGo/SettingsNextStepsView.swift:25-58`; `iOS/DuckDuckGo/SettingsCompleteSetupView.swift:24-81`; `iOS/DuckDuckGo/SettingsSubscriptionView.swift:88-185,250-299,416-466` | **Not presentation-queued by default.** Treat remote enable/order as Settings IA policy, not transient promo arbitration. PIR badge is the class-(b) exception above. |
| Return-to-Tab and tab-switcher tracker count | Active utilities, not promotional asks. Return-to-Tab already exposes `ntpAfterIdleState`; tracker count is a hideable seven-day privacy statistic. `iOS/DuckDuckGo/AppLifecycle/IdleReturnEligibilityManager.swift:25-47,95-116`; `iOS/DuckDuckGo/EscapeHatchView.swift:22-43`; `iOS/DuckDuckGo/TabSwitcherTrackerCountViewModel.swift:52`; `iOS/DuckDuckGo/UserText.swift:1625-1645` | **External/visibility registration for conflict awareness**, not RMF migration. |
| Broken-site prompt | Reactive site-problem prompt with a local limiter. `iOS/DuckDuckGo/MainViewController.swift:2931-2935` | Future presentation permission on the event; not remote content. |
| Inactivity retention notification | Privacy-config-gated provisional local notification, rescheduled on resume after a remote-tunable inactivity interval (default seven days). `iOS/DuckDuckGo/AppServices/InactivityNotificationSchedulerService.swift:25-34,58-82,99-140` | **Client-side, outside the in-app queue.** It is OS notification scheduling; launch-source gating should continue to prevent a second prompt after notification launch. |
| Post-import passwords/bookmarks continuation cards | Import-summary footer immediately offers the complementary data type missing from the current import session before the Sync card. `iOS/DuckDuckGo/DataImport/DataImportSummaryViewModel.swift:84-124,127-147` | Transactional/session-local; keep content and trigger local, and expose it to a future import-summary arbiter only if needed. |

### B.5 Canonical inventory field-completeness ledger

This ledger makes the RQ2 fields explicit. Detailed trigger/gap evidence remains in §§B.2–B.4; “guidance” refers to the reported rules at `promo-queue-docs/iteration_2_research.md:43-55` and is therefore **reported (Asana), not code-verifiable**.

| Canonical unit | Surface / trigger | Config source | State, pacing, and guidance comparison | Final disposition |
|---|---|---|---|---|
| RMF NTP channel / win-back urgency | NTP on normal/after-idle fetch; local offer state feeds urgency. `iOS/DuckDuckGo/HomePageConfiguration.swift:56-82`; `SharedPackages/BrowserServicesKit/Sources/Subscription/WinBackOffer/WinBackOfferVisibilityManager.swift:96-109` | RMF JSON + hardcoded matcher vocabulary | RMF shown/dismissed state; permanent dismiss; optional relative expiry; **no cap/global pace**. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:255-275,324-369` | **(a)** already RMF; iteration-1 NTP visibility permit |
| What's New | Launch modal provider fetches `.modal`; Settings can replay. `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:56-75` | RMF `cards_list` + on-demand feature flag | Burned shown+dismissed on presentation; no live campaign. | **(a)** already RMF path; existing native modal provider |
| Win-back launch | Launch sheet on eligible churned subscription. `SharedPackages/BrowserServicesKit/Sources/Subscription/WinBackOffer/WinBackOfferVisibilityManager.swift:111-165` | Privacy flag + hardcoded state machine | Keychain/KV offer, churn, redemption; five-day offer; 270-day churn-reset rule. | **(c)** existing local provider; future internal candidate if needed |
| Subscription reinstaller | Launch sheet, returning/skipped user after ≥7 days. `iOS/DuckDuckGo/SubscriptionPromo/SubscriptionPromoCoordinator.swift:42-84,125-133` | Two privacy flags + app variant | Local once-ever shown key; stricter than repeat guidance. | **(b)** modal + skipped-onboarding matcher |
| Address-bar picker | Launch forced-choice sheet after local AI/onboarding/state checks. `iOS/DuckDuckGo/AIChat/NewAddressBarPicker/NewAddressBarPickerDisplayValidator.swift:69-145` | Privacy flag + hardcoded logic | App-group once-ever shown key; writes chosen setting. | **(c)** existing local provider |
| Default Browser active/reactivation | Launch sheet/full-screen based on live OS and activity state. `iOS/LocalPackages/SetDefaultBrowser/Sources/SetDefaultBrowserCore/PromptDecider/DefaultBrowserPromptTypeDecider.swift:138-185` | Privacy flag/settings | KeyValueFiles activity ledger; active repeats at 14 active days; permanent don't-ask. **14 days is shorter than reported ≥28 guidance.** | **(c)** existing local provider |
| Cookie opt-in | Launch consent sheet after install/state/count checks. `iOS/DuckDuckGo/ModalPromptCoordination/Providers/CookiePopupProtectionOptInModalPromptProvider.swift:88-185` | Two privacy flags + local preference | Local shown count cap 3, confirmation, first date; setting mutation. No hard time expiry. | **(b)** consent modal/state/action/cap gaps |
| VPN expired alert | Resume/live entitlement event. `iOS/DuckDuckGo/AppServices/VPNService.swift:59-100` | Local runtime entitlement state | One-shot group-default flag; essential/transactional, not promo-paced. | **(c)** local; essential observer/preemption contract |
| Sync · Bookmarks | Bookmarks-list header when >0 and sync inactive. `iOS/DuckDuckGo/BookmarksViewController.swift:943-988` | Privacy flags + hardcoded local eligibility | Permanent dismissal; no cap/expiry. | **(b)** bookmarks-header bridge |
| Sync · Passwords | Passwords header when accounts exist and sync inactive. `iOS/DuckDuckGo/AutofillLoginListViewModel.swift:328-336` | Privacy flags + hardcoded local eligibility | Permanent dismissal; no cap/expiry; private header priority. | **(b)** passwords header + credential count |
| Sync · Import summary | Immediate summary footer after successful import. `iOS/DuckDuckGo/DataImport/DataImportSummaryViewModel.swift:84-124` | Privacy flag + session state | Permanent dismissal; no cap/expiry; event timing. | **(b)** summary bridge + matcher/latency |
| Sync · Duck.ai | Live switch-bar card with chats/current UI. `iOS/DuckDuckGo/AIChat/InputBox/SwitchBar/Suggestions/AIChatSyncPromoViewModel.swift:49-75` | Privacy flags + local UI state | Local dismissed/impressions, cap 3; courtesy modal deferral. | **(b)** Duck.ai bridge + state/cap/latency |
| Password import header | Passwords header, iOS ≥18.2, <25, no import. `iOS/DuckDuckGo/CredentialsImport/AutofillCredentialsImportPresentationManager.swift:93-141` | Privacy flag + local vault/import state | Permanent dismissal; no cap/expiry; header priority 1. | **(b)** header + credential/import attributes |
| Password import sheet | Page/Autofill no-credential event. `iOS/DuckDuckGo/TabViewController.swift:4432-4479` | Privacy flag + local vault/domain state | Cap 5, per-domain/never/permanent dismissal. | **(c)** local event; future permission seam |
| Autofill extension header | Passwords header after install/count/provider checks. `iOS/DuckDuckGo/AutofillExtensionPromotion/AutofillExtensionPromotionManager.swift:88-149,262-309` | Privacy flag with remote thresholds | Permanent dismissal; unlimited before dismissal; header priority 4. | **(b)** header + provider/count; first-class action gap |
| Autofill extension sheet | Post-login detection/page event. `iOS/DuckDuckGo/TabViewController.swift:2424-2440,4482-4511` | Privacy flag + live provider/domain state | Cap 5, permanent later, domain dedupe. | **(c)** local event; future permission seam |
| Autofill survey | Passwords header; first uncompleted remote survey. `iOS/DuckDuckGo/AutofillSurveyManager.swift:35-78,84-125` | Privacy-config settings list, not RMF | Completed-ID store; CTA/dismiss both complete; header priority 2. | **(b)** header + survey parameter mapping |
| Email signup | Content-scope callback presents local bottom sheet. `iOS/DuckDuckGo/MainViewController+Email.swift:104-133` | Privacy flag + English gate | Permanent “don't show” timestamp; ordinary close has no cap/expiry. | **(c)** local event; future permission seam |
| Home-row reminder | Floating banner after >3 days and onboarding condition. `iOS/DuckDuckGo/HomeRowReminder.swift:23-69,74-115` | Hardcoded; no kill flag | First-access + shown keys; once-only, no expiry needed after display. | **(b)** floating bridge + onboarding matcher |
| App rating | StoreKit request on DDG SERP after unique-use days. `iOS/DuckDuckGo/TabViewController.swift:1959-1966` | Privacy flag | Core Data; first after 3 days, second after 4 more, max 2. | **(c)** future permission seam, local system UI |
| Duck Player pills/toast | Live YouTube/per-video navigation; toast after dismissals. `iOS/DuckDuckGo/DuckPlayer/NativeUI/DuckPlayerNativeUIPresenter.swift:517-555,642-666` | Feature/runtime settings | Duck Player settings and per-video state; toast at exactly 3 dismissals. | **(c)** visibility observer |
| Duck Player explainer | User-invoked SERP/YouTube info sheet. `iOS/DuckDuckGo/DuckPlayer/DuckPlayer.swift:695-720` | Hardcoded feature UI | No promotional recurrence policy; user initiated. | **(c)** optional user-initiated registration |
| VPN menu dot | Browsing-menu row on build for non-subscriber. `iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift:917-960` | Privacy flag | UserDefaults prefix; cap 4; no time expiry. | **(b)** menu-dot bridge + cap |
| VPN TipKit family | Inline tips driven by live VPN state. `iOS/DuckDuckGo/VPNTipsModel.swift:29-80,98-126` | Feature/runtime logic | TipKit store/rules; local interaction lifetime. | **(c)** observe in owning surface |
| Settings Complete Setup | Persistent default/import rows on Settings appearance. `iOS/DuckDuckGo/SettingsCompleteSetupView.swift:24-81` | Local eligibility + feature settings | Permanent swipe dismissals; no 14-day rule. | **(c)** Settings IA, not transient queue |
| Settings Next Steps | Four always-mounted rows. `iOS/DuckDuckGo/SettingsNextStepsView.swift:25-58` | Hardcoded availability/feature state | No dismissal/expiry, which conflicts if treated as promos. | **(c)** human must classify as IA vs promo |
| Subscription/win-back Settings | Persistent state-driven purchase/resubscribe rows/badge. `iOS/DuckDuckGo/SettingsSubscriptionView.swift:88-185,250-299,416-466` | Subscription runtime + feature flags | State-driven; standard rows do not expire independently. | **(c)** Settings IA |
| PIR `NEW` badge | Settings badge on eligible PIR rows. `iOS/DuckDuckGo/SettingsSubscriptionView.swift:217-227,342-370` | Feature flag + release-window config | First-impression date; 7 days/3 minor releases. | **(b)** Settings-badge bridge/lifecycle |
| Return-to-Tab / tracker count | After-idle NTP utility / tab-switcher statistic. `iOS/DuckDuckGo/AppLifecycle/IdleReturnEligibilityManager.swift:95-116`; `iOS/DuckDuckGo/TabSwitcherTrackerCountViewModel.swift:52` | Privacy features/local settings | User-hide/local state; not promotional asks. | **(c)/NP** visibility-only conflict awareness |
| Broken-site prompt | Reactive site-problem event. `iOS/DuckDuckGo/MainViewController.swift:2931-2935` | Privacy settings + local limiter | Limiter store; transactional/reactive. | **(c)** future local permission seam |
| Inactivity notification | Resume schedules OS notification after inactivity. `iOS/DuckDuckGo/AppServices/InactivityNotificationSchedulerService.swift:25-34,58-82,99-140` | Privacy flag + remote days setting | Replaced/rescheduled pending request; one-shot trigger. | **(c)** outside in-app queue |
| Post-import continuation cards | Immediate summary footer for missing passwords/bookmarks. `iOS/DuckDuckGo/DataImport/DataImportSummaryViewModel.swift:84-124,127-147` | Privacy feature + import-session state | Session-local priority before Sync; no independent recurrence. | **(c)** local import-summary candidate |

#### Exact storage identifiers

“No dedicated state” means eligibility is recomputed from feature/runtime data rather than a persisted promo record.

| Canonical unit(s) | Store / exact persisted property or key |
|---|---|
| RMF NTP and What's New | RMF Core Data `RemoteMessageManagedObject` fields `id`, `message`, `status`, `shown`, `firstShownDate`, `surfaces`; What's New replay additionally uses `com.duckduckgo.whatsNew.lastShownMessage`. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/CoreData/RemoteMessaging.xcdatamodeld/RemoteMessaging 3.xcdatamodel/contents:3-14`; `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:42-74` |
| All six launch providers (shared pacing) | `com.duckduckgo.prompts.lastPromptShownTimestamp`. `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromptCooldownStore.swift:31-60` |
| Win-back launch/urgency | Keychain service `com.duckduckgo.winback-offer`, accounts suffixed `churnDate`, `offerRedemption`, `offerPresentationDate`; KV `winback-offer.did-dismiss-urgency-message`. `SharedPackages/BrowserServicesKit/Sources/Subscription/WinBackOffer/WinBackOfferStore.swift:35-63,90-124` |
| Subscription reinstaller | `com.duckduckgo.ios.daxPrivacyProPromotionDialogShown` through `DaxDialogsSettings.subscriptionPromotionDialogShown`. `iOS/Core/UserDefaultsPropertyWrapper.swift:60`; `iOS/DuckDuckGo/DaxDialogsSettings.swift:108` |
| Address-bar picker | `aichat.storage.newAddressBarPickerShown.v2` (legacy key also declared). `iOS/DuckDuckGo/AIChat/NewAddressBarPicker/NewAddressBarPickerDisplayValidator.swift:159-181` |
| Default Browser prompts | `com.duckduckgo.defaultBrowserPrompt.lastModalShownDate`, `.modalShownOccurrences`, `.modalPermanentlyDismissed`, `.inactiveModalShown`, `.userType`, `.userActivity`. `iOS/DuckDuckGo/DefaultBrowserPrompt/PromptActivity/DefaultBrowserPromptActivityKeyValueFilesStore.swift:29-33`; `iOS/DuckDuckGo/DefaultBrowserPrompt/UserType/DefaultBrowserPromptUserTypeManager.swift:70`; `iOS/DuckDuckGo/DefaultBrowserPrompt/UserActivityManager/DefaultBrowserPromptUserActivityKeyValueFilesStore.swift:42` |
| Cookie opt-in | `com.duckduckgo.cookiePopupProtection.optIn.shownCount`, `.firstShownDate`, `.hasConfirmed`; selected preference uses `com.duckduckgo.ios.cookiePopupPreference`. `iOS/DuckDuckGo/ModalPromptCoordination/Providers/CookiePopupProtectionOptInModalPromptProvider.swift:28-58`; `iOS/Core/UserDefaultsPropertyWrapper.swift:117-118` |
| VPN expired entitlement | Network-protection group defaults `showEntitlementAlert`, `showEntitlementNotification`, `suppressEntitlementMessaging`; Darwin notification `com.duckduckgo.network-protection.entitlement-messaging-changed`. `SharedPackages/VPN/Sources/VPN/Settings/Extensions/UserDefaults+showMessaging.swift:24-108` |
| Sync Bookmarks / Passwords / Data Import | `com.duckduckgo.app.sync.PromoBookmarksDismissed`, `.PromoPasswordsDismissed`, `.PromoDataImportDismissed`. `iOS/Core/UserDefaultsPropertyWrapper.swift:108-110` |
| Sync Duck.ai | `sync-promo-ai-chat-dismissed`, `sync-promo-ai-chat-impressions` in the typed `UserDefaults.app` keyed store. `iOS/DuckDuckGo/SyncPromoManager.swift:37-45,78-92` |
| Password Import header + in-browser sheet | `com.duckduckgo.logins.hasImportedLogins`, `.isCredentialsImportBrowserPromptPermanentlyDismissed`, `.isCredentialsImportPasswordsPromoPermanentlyDismissed`, `.credentialsImportPromptPresentationCount`; per-domain dedupe is in-memory. `iOS/DuckDuckGo/AutofillLoginImportState.swift:25-31,45-99` |
| Autofill Extension header + sheet | `com.duckduckgo.autofill.extension.promo.passwords.dismissed`, `.browser.dismissed`, `.browser.presentationCount`; domain dedupe is `domainExtensionPromptLastShownOn` in memory. `iOS/DuckDuckGo/AutofillExtensionPromotion/AutofillExtensionPromotionManager.swift:40-76,228-259` |
| Autofill Survey | `com.duckduckgo.app.autofill.SurveysCompleted`. `iOS/Core/UserDefaultsPropertyWrapper.swift:103`; `iOS/DuckDuckGo/AutofillSurveyManager.swift:35-78` |
| Email signup | `Autofill.InContextEmailSignup.dismissed.permanently.at`. `SharedPackages/BrowserServicesKit/Sources/BrowserServicesKit/Email/EmailManager.swift:180`; `iOS/DuckDuckGo/EmailSignupPromptViewController.swift:29-40` |
| Home-row reminder | `com.duckduckgo.homerow.reminder.firstAccessDate`, `com.duckduckgo.homerow.reminder.shown`. `iOS/DuckDuckGo/HomeRowReminder.swift:74-115` |
| App rating | Core Data entity `AppRatingPromptEntity`: `firstShown`, `lastShown`, `lastAccess`, `uniqueAccessDays`. `iOS/DuckDuckGo/AppRatingPrompt.swift:85-163` |
| Duck Player pills/toast | App UserDefaults `com.duckduckgo.ios.duckPlayerPillDismissCount`, `.duckPlayerWelcomeMessageShown`, `.duckPlayerPrimingMessagePresented`, `.duckPlayerNativeUIWasUsed`; per-video `DuckPlayerState.hasBeenShown` is in-memory. `iOS/DuckDuckGo/AppUserDefaults.swift:118-127`; `iOS/DuckDuckGo/DuckPlayer/NativeUI/DuckPlayerState.swift:24-29` |
| Duck Player user-invoked explainer | No dedicated persisted promo state; presentation is user-invoked. `iOS/DuckDuckGo/DuckPlayer/DuckPlayer.swift:695-720` |
| VPN menu dot | `vpn-menu-item.free-trial-badge.view-count` (prefix + `free-trial-badge.view-count`), maximum 4. `iOS/DuckDuckGo/Subscription/FreeTrials/VPNSubscriptionPromotionHelper.swift:83-90`; `SharedPackages/BrowserServicesKit/Sources/Subscription/FreeTrials/FreeTrialBadgePersistor.swift:28-63` |
| VPN TipKit family | TipKit's own datastore; no app-owned promo key is declared in the tips model. `iOS/DuckDuckGo/VPNTipsModel.swift:29-80,98-126` |
| Settings Complete Setup | `com.duckduckgo.settings.setup.browser-default-dismissed`, `.import-passwords-dismissed`, `.check-browser-default`. `iOS/DuckDuckGo/SettingsViewModel.swift:1401-1442` |
| Settings Next Steps | No dedicated persisted promo state; the four rows are always mounted subject to feature availability. `iOS/DuckDuckGo/SettingsNextStepsView.swift:25-58` |
| Subscription/win-back Settings rows | No separate row-impression eligibility key; rows derive from subscription manager state and the win-back store above. `iOS/DuckDuckGo/SettingsSubscriptionView.swift:416-466`; `iOS/DuckDuckGo/SettingsViewModel.swift:1728` |
| PIR `NEW` badge | `firstImpressionDatePIRNewBadge`. `iOS/DuckDuckGo/NewBadge/NewBadgeVisibilityManager.swift:25-31,93-101` |
| Return-to-Tab | Typed keys `idle-return-after-inactivity-option`, `idle-return-new-user`, `idle-return-interval-seconds`, `idle-return-last-tab-shortcut-enabled`. `iOS/DuckDuckGo/AppLifecycle/AfterInactivitySettingStorage.swift:23-36` |
| Tab-switcher tracker count | `com.duckduckgo.ios.tabswitcher.showTrackerCount`, `com.duckduckgo.ios.tabswitcher.lastTrackerCount`. `iOS/DuckDuckGo/TabSwitcherSettings.swift:32-64` |
| Broken-site prompt | `com.duckduckgo.ios.userBehavior.lastBrokenSiteToastShownDate`, `com.duckduckgo.ios.userBehavior.toastDismissStreakCounter`. `iOS/DuckDuckGo/BrokenSitePromptLimiterStore.swift:24-30`; `iOS/Core/UserDefaultsPropertyWrapper.swift:165-166` |
| Inactivity notification | No promo history key; pending UN notification identifier `com.duckduckgo.inactivity.notification`, with remote setting name `daysInactive`. `iOS/DuckDuckGo/AppServices/InactivityNotificationSchedulerService.swift:25-34,99-140` |
| Post-import continuation cards | No persisted promo state; derives from `sessionImportedDataTypes` and current summary values for the import session. `iOS/DuckDuckGo/DataImport/DataImportSummaryViewModel.swift:60-65,110-147` |

### B.6 Reconciliation of all 74 product-list names

The names in this subsection are **reported (Asana), not code-verifiable**; source: `promo-queue-docs/iteration_2_research.md:57-69`. Status legend: **A** active distinct unit, **D** duplicate/renamed/wrong surface, **S** stale/no current iOS counterpart, **NP** active but not a promo, **X** removed/non-built, **OS** other platform.

| Product group | Reconciled status in current iOS code | Code evidence |
|---|---|---|
| **Modals/sheets:** Win Back Promotion A; Subscription Promotion (Returning Users) A; VPN Expired Entitlement Alert A; Default Browser Prompt D umbrella; Set As Default Browser—Active A; Default Browser Reactivation A; What's New A/RMF; AI Chat Address Bar Choice D; New Address Bar Option Bottom Sheet A; App Enjoyment/Rating A; Enable Credential Provider Extension A; Import Passwords Sheet A; Privacy Pro Promo (Skipped Onboarding) D; Win-Back Prompt D; Browser Comparison D | Five duplicate/umbrella labels collapse into the canonical launch, default-browser, and picker rows above. The picker is still factory-registered. | `iOS/DuckDuckGo/ModalPromptCoordination/Factory/PromoCoordinationFactory.swift`; `iOS/DuckDuckGo/AppServices/VPNService.swift`; `iOS/DuckDuckGo/AppRatingPrompt.swift` |
| **NTP/cards:** Return to Tab NP; Add to Home Screen D (floating banner); Default Browser NTP Message S; Indonesia Regional Card S; Sync Chat D (Duck.ai); Bookmarks Sync D (header); Sync Passwords D (header); Sync Bookmarks D; 7-Day Trackers Blocked D/NP (tab-switcher statistic) | Product surfaces/names drifted; legacy local NTP messages are empty and current NTP message content is RMF-only. | `iOS/DuckDuckGo/HomeMessageStorage.swift:30-33`; `iOS/DuckDuckGo/EscapeHatchView.swift:22-43`; `iOS/DuckDuckGo/MainViewController.swift:2906-2920`; `iOS/DuckDuckGo/TabSwitcherTrackerCountViewModel.swift:52` |
| **Next Steps/Settings:** Next Steps Hide (14 Days) S; Voice Search D row; Address Bar D row; Add Widget D row; Import Google Passwords D/generic; Get Desktop Browser S; Next Steps A umbrella; Complete Setup A; Subscription Settings Promo A; Settings—VPN Status NP | Next Steps has four always-mounted rows; Complete Setup has default browser + generic import. There is no 14-day hide or desktop-browser row. | `iOS/DuckDuckGo/SettingsNextStepsView.swift:25-58`; `iOS/DuckDuckGo/SettingsCompleteSetupView.swift:24-81`; `iOS/DuckDuckGo/SettingsRootView.swift:68-84` |
| **Passwords-list:** Import Passwords Promo A; Sync Promo A; Extension Promo A; Autofill Survey A; Survey in Passwords D; Import Passwords in Passwords D; Import Passwords from Google D/generic | Seven names collapse to four active headers in a private priority chain. | `iOS/DuckDuckGo/AutofillLoginListViewController.swift:746-795`; `iOS/DuckDuckGo/AutofillLoginListViewModel.swift:328-390` |
| **Menu/badge/dot:** VPN Row A; Fire Tabs X; Default Browser Row S; Win-Back Badge A; Identity Theft `NEW` Badge D (actually PIR); Browsing Menu Dot S; Browser Menu Button Blue Dot D/NP onboarding; Tab Switcher Dot S; Tab Switcher Unread Dot NP; Downloads Dot D/NP; Downloads Menu Row Dot NP; Tabs Toolbar Highlight NP onboarding; PIR Beta Pill S/D; VPN Try-for-Free Pill S/D (actual dot); Subscription Upsell Banner OS; Sync Row Warning NP | Only the VPN promo dot, win-back badge, and PIR `NEW` badge are promo-like active units; downloads/unread/warning indicators are state, not promotion. Fire code is absent from the Xcode project and hardcoded ineligible. | `iOS/DuckDuckGo/TabViewControllerMenuBuilderExtension.swift:917-960`; `iOS/DuckDuckGo/SettingsSubscriptionView.swift:88-124,217-227`; `iOS/DuckDuckGo/FireMode/FireModePromotionsCoordinator.swift:120-180`; `iOS/DuckDuckGo/SettingsViewModel.swift:1256-1269` |
| **Duck Player:** Introduction D; Toast A; Native UI Welcome A; Feature Explainer A | Priming modal view is unreferenced, but native pills/toast and the separate user-invoked explainer are active. | `iOS/DuckDuckGo/DuckPlayer/NativeUI/DuckPlayerNativeUIPresenter.swift:517-555,642-666`; `iOS/DuckDuckGo/DuckPlayer/Modal/DuckPlayerModalPresenter.swift:24-47` |
| **Promo plugins:** Bookmark Added with Sync Promo D/partial; Bookmark Confirmation with Promo Plugins D/partial; Duck AI Address Bar Option D | Plain bookmark confirmation remains; no current Swift promo-plugin implementation. Duck AI label maps to the picker. | `iOS/DuckDuckGo/TabViewControllerSaveBookmarkExtension.swift`; `iOS/DuckDuckGo/ModalPromptCoordination/Factory/PromoCoordinationFactory.swift` |
| **Other:** Email Protection Sign-Up A; Widget Instructions NP; Home Screen Widget Auto-Add S; Favorites Add Instructions NP/onboarding; Broken Site Prompt A/(c); Cookie Consent Notifications NP/ambiguous; App Tracking Protection Tracker Badges OS; Privacy Status Indicators NP; Tab Switcher Tracker Count NP; Trackers Blocked Animation NP | Do not silently equate “Cookie Consent Notifications” with Cookie Pop-up Protection opt-in; human confirmation is needed. | `iOS/DuckDuckGo/Widgets/Education/WidgetEducationView.swift:24-80`; `iOS/DuckDuckGo/MainViewController.swift:2931-2935`; `iOS/DuckDuckGo/OmniBarViewController.swift:500-551`; `iOS/DuckDuckGo/TabSwitcherTrackerCountViewModel.swift:52` |

**Shadow promos/attention units missing or unclear in the product list:** Cookie Pop-up Protection opt-in; Sync on the data-import summary; VPN Add Widget/Snooze/Geoswitch TipKit tips; inactivity retention notification; live RMF surveys/PIR/YouTube cards/win-back urgency; and the current post-import continuation card. `iOS/DuckDuckGo/ModalPromptCoordination/Providers/CookiePopupProtectionOptInModalPromptProvider.swift:88-185`; `iOS/DuckDuckGo/DataImport/DataImportSummaryViewModel.swift:84-124`; `iOS/DuckDuckGo/VPNTipsModel.swift:29-80,98-126`; `iOS/DuckDuckGo/AppServices/InactivityNotificationSchedulerService.swift:25-34,58-82,99-140`; `remote-messaging-config/live/ios-config/ios-config.json:5-860`

---

## C. RQ3 — ranked named gaps

Counts use the **12 class-(b) canonical rows** in §B.3. A promo can have more than one gap, so counts do not sum to 12.

| Rank | Named gap | Active units unblocked/affected | What closes it | Effort |
|---:|---|---:|---|---|
| 1 | **Native-surface ↔ RMF visibility/content bridge** | **12** | Define per-message/per-surface active state, native renderer contract, shown/dismiss/action ownership, and an arbitration seam. This is the umbrella prerequisite; exact surfaces follow below. | **M foundation + S per promo**, app release |
| 2 | **Local-state matching attributes** | **8** | Add privacy-clean attributes for skipped onboarding; cookie state/count; credentials/import/provider state; import event; Duck.ai current state; home onboarding. | **S each**, app release |
| 3 | **Header/card/chrome surfaces** | **7** | Native hybrid integrations for bookmarks, passwords, import summary, and Duck.ai chrome. A shared passwords-header queue immediately covers four. | **M shared + S each**, app release |
| 4 | **Per-message impression/view cap** | **3** | Add cap policy to the client queue or RMF; preserve current Cookie (3), Duck.ai (3), VPN dot (4) behavior. | **M policy**, app/config |
| 5 | **Generic promotional/consent modal** | **2** | Prefer native hybrid sheets first; a true RMF renderer requires template/schema/action semantics and queue integration. | **M–L**, app release |
| 6 | **First-class-renderer action gap** | **2** | Cookie preference mutation and precise Autofill extension-management navigation would be required for full RMF rendering; the proposed hybrids keep both local. | **S each** if pursued, app release |
| 7 | **Event-driven evaluation / ≤24h latency** | **2** | Data-import and Duck.ai variants keep local eligibility or gain named client re-evaluation events. | **S hybrid / L general**, app release |
| 8 | **Floating banner, menu dot, Settings badge** | **1 each** | Reuse the hybrid contract; native views remain renderers. | **S each after foundation**, app release |
| 9 | **Survey parameter mapping (`saved_passwords`)** | **1** | Extend the allowlist, or retain native URL enrichment in the proposed hybrid. | **S**, app release only for first-class mapping |

Closing “surfaces” alone does not finish a migration: matcher/action/cap rows above are the second-order work. Conversely, building first-class RMF renderers for every tiny badge is unnecessary if the hybrid contract is accepted.

---

## D. RQ3 and RQ5 — draft migration sequence and effort model

### Wave 0 — recognize what is already remote (config/process only)

- Treat the RMF NTP channel and What's New content path as already migrated; document the current 10 live iOS IDs and their queue surface registration. `remote-messaging-config/live/ios-config/ios-config.json:5-860`
- Fix schema drift before scaling authoring. `remote-messaging-config/schemas/ios/schema.json:177-229,350-360,389-429`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/JsonRemoteMessagingConfig.swift:76-99,116-129`
- Retire folklore: Sync navigation is available. `iOS/DuckDuckGo/MessageNavigator.swift:50-72`

**Effort: S. Release: config/process only unless schema/client compatibility is tightened.**

### Wave 1 — hybrid contract + seven header/card promos

Build the native-surface/RMF contract and explicit surface contexts, then migrate Sync Bookmarks, Sync Passwords, Sync Data Import, Sync Duck.ai, Password Import header, Autofill Extension header, and Autofill Survey header. Preserve immediate local eligibility and existing header priority while moving content/targeting/kill into RMF. The final visibility owner is an iteration-3 decision.

**Effort: M foundation, then S per promo across RMF/iOS/measurement review. Release-gated.** This is a relative research class, not a delivery estimate.

This wave is urgent because bookmarks/passwords/data-import Sync and the extension/import headers have no impression cap or hard expiry, while the four passwords promos use a private priority chain invisible outside that screen. `iOS/DuckDuckGo/SyncPromoManager.swift:141-171`; `iOS/DuckDuckGo/AutofillLoginListViewController.swift:746-795`

### Wave 2 — small attention surfaces

Apply the same contract to Home-row, VPN menu dot, and PIR `NEW` badge. Keep current local one-shot/cap/expiry behavior until the queue owns equivalent policy.

**Effort: S per promo after the Wave 1 foundation. Release-gated.**

### Wave 3 — modal candidates

Prototype the Subscription reinstaller sheet as a hybrid RMF-scheduled native sheet. Only then decide whether a generic RMF modal renderer is worth the larger schema/template/measurement investment. Cookie opt-in stays native for consent/action semantics but can inherit remote scheduling/kill via the hybrid.

**Effort: M hybrid prototype; M–L for a reusable first-class modal surface. Release-gated.**

### Wave 4 — register, do not migrate

After iteration 3 chooses the long-term owner, bring class-(c) collision-capable units under its permission/visibility contract: launch providers, StoreKit rating, in-browser import/extension, Email signup, Duck Player, VPN alert (with essential preemption), and reactive broken-site prompts. Persistent Settings IA and non-promo utilities are observed only where their visibility matters.

**Effort: S per adapter after queue contexts/events exist; several parallel follow-ups. Release-gated.**

### Effort and release legend

| Change | Class | App release? |
|---|---|---|
| Existing NTP template + current matcher/action | S / config-only | No |
| New navigation target or matcher | S | Yes |
| Native hybrid keyed to RMF state | S–M | Yes |
| True new RMF surface | M per platform | Yes |
| Generic event-driven re-evaluation | L cross-platform | Yes |
| Multi-message/per-surface RMF scheduling | L | Yes |
| Schema/CI cleanup | S–M | Coordinated; not always runtime |

Risks:

- **Latency:** event-driven variants can regress by up to 24 hours if local eligibility is naively moved into RMF. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessagingConfig.swift:24-45`
- **Requirement loss:** any simplification must record what was dropped; Fire Mode's accepted trade-off is **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:34,73-83`
- **Release coupling/divergence:** every new hardcoded attribute/action is version-gated; absent Android/Windows schemas make cross-platform review harder. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:415-423`; `remote-messaging-config/schemas/`
- **Measurement discontinuity:** bespoke pixels and RMF pixels have different names/semantics; modal messages are burned shown+dismissed on presentation. `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:67-75`; `iOS/DuckDuckGo/Pixels/RemoteMessagingPixelReporter.swift:31-43`
- **Single-message starvation:** one high-priority RMF message can monopolize all RMF surfaces until dismissal, expiry, or config replacement/removal. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:443-506`

---

## E. RQ4 — division of labor: what RMF migration does not solve

| Responsibility | RMF migration buys | Client-side arbiter must do if iteration 3 selects one | Neither does today |
|---|---|---|---|
| Content/control | Remote copy, inline translations, images, targeting, config removal/kill. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:440-455`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingImageProvider.swift:27-61` | Decide visibility now when local UI conflicts; delay rather than lose eligible work. Iteration 1 proves this only for NTP RMF versus launch modals. macOS's ExternalPromo observes a surface but does not gate RMF itself. `macOS/DuckDuckGo/Promotions/PromoTypes/Promo.swift:97-114`; `macOS/DuckDuckGo/RemoteMessaging/RemoteMessagePromoDelegate.swift:23-80` | Atomic policy/content rollout across all app versions. |
| Arbitration | First eligible RMF message by JSON order. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:51-78` | Priority versus non-RMF promos; severity/context conflicts; app/user cooldowns; same-surface private chains. `macOS/DuckDuckGo/Promotions/PromoService.swift:488-553`; `macOS/DuckDuckGo/Promotions/PromoTypes/PromoInitiated.swift:21-34` | Essential-message preemption contract; owner-visible delay reasons. These requirements are **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:43-55` |
| Frequency/expiry | Permanent dismissal and optional days-after-first-show expiry. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:255-264,324-369` | Per-promo next eligibility/history and global pacing. `macOS/DuckDuckGo/Promotions/PromoHistoryStoring.swift`; `macOS/DuckDuckGo/Promotions/PromoService.swift:488-553` | Enforced impression caps and absolute campaign windows across both systems. |
| Measurement | Shown/unique/dismiss/action pixels; CTR is computable. `iOS/DuckDuckGo/HomePageConfiguration.swift:99-123`; `iOS/DuckDuckGo/NewTabPageMessagesModel.swift:121-155` | Delayed/suppressed/eligible-not-shown accounting and deduplication with RMF pixels. | Standard owner dashboard and a single attribution contract. |

**Corrected integration statement:** iteration 1 does not create an iOS `ExternalPromo` path or a shared `PromoQueue` package. It adds a narrow app-level permit coordinator between the existing launch-modal group and actually visible NTP RMF. Future NTP messages benefit at the surface level, but every new RMF/native surface still needs explicit visibility, accounting, and arbitration integration. macOS's observation-only pattern is comparison evidence only: `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+RemoteMessage.swift:24-46`.

---

## F. Questions for humans — do not infer product intent

1. Is ≤24-hour re-evaluation acceptable per promo, or must Data Import and Duck.ai always keep immediate local eligibility?
2. Are the stale product entries (Indonesia card, Default Browser NTP message, Get Desktop Browser, home-screen widget auto-add, old dots/pills) intentionally retired, or candidates for resurrection?
3. Does “Cookie Consent Notifications” mean the active Cookie Pop-up Protection opt-in sheet? The code and product names do not establish that mapping.
4. Should the VPN expired-entitlement alert be in promo scope? If yes, what is the essential-message preemption rule, and must it bypass all cooldowns?
5. Are persistent Settings Next Steps/Complete Setup/subscription rows “promos” subject to expiry/queueing, or product navigation IA outside transient arbitration?
6. Is a hybrid native renderer an acceptable RMF migration, or does “migrated” require a first-class RMF renderer?
7. For Cookie opt-in, may remote config ever select a preference-changing action, or must consent mutation remain exclusively local?
8. Should default-browser active reminders retain their current 14-active-day recurrence, or align with the reported ≥28-day guideline?
9. Is RMF `expVariant` an approved experiment mechanism going forward, or legacy compatibility that should not be expanded?
10. Which system owns shown/dismiss/action pixels for hybrids, and where do owners see delayed/eligible-not-shown counts?
11. Must RMF move from one global scheduled message to per-surface scheduling before the first non-NTP hybrid ships, or is deliberate single-message serialization acceptable initially?
12. Who approves new matcher/action/surface proposals cross-platform, and who owns the config/queue contract as an AOR?

---

## G. RQ coverage

- **RQ1:** §A — templates, surfaces, attributes, actions, lifecycle, localization, pixels, live configs.
- **RQ2:** §B.2–B.6 — canonical code inventory, explicit surface/trigger/config/storage/pacing fields, all 74 reported product names, stale and shadow findings.
- **RQ3:** §B–D — final (a)/(b)/(c), named gaps, counts, migration waves.
- **RQ4:** §E — division of labor and corrected queue/RMF seam.
- **RQ5:** §C–D — effort classes, release gates, sequence, and risks.
