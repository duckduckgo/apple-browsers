# RMF gap analysis — iteration 2

**Decision pre-read · original research 2026-07-30; PR 1 status refreshed 2026-08-04**

**Apple checkout:** `7fdd4719a1` on `origin/main` (merged PR [#6087](https://github.com/duckduckgo/apple-browsers/pull/6087), 2026-08-04).
**RMF config checkout:** `5764096` on `main` (2026-07-29).

> **Source rule.** Code and config claims cite these checkouts with `file:line`. Statements from Asana threads are marked **reported (Asana), not code-verifiable**. Effort classes: **S** = bounded days, **M** = coordinated multi-component work, **L** = architectural/multi-release — relative classes, not delivery commitments.

> **Iteration-1 status note (affects several claims below).** The seven-provider modal chain and its cooldown shipped to `main` **ungated** in Nov 2025 (`105dd6cf34` #2337). PR 1 is on `main`: the disabled-by-default `FeatureFlag.promoPresentationCoordination` mapping, `PromoCoordinationService`, `PromoCoordinationFactory`, the app-scoped lease arbiter, modal admission/phases, NTP-facing admission/retry seam, and focused coverage landed in `7fdd4719a1`. In final PR 2 the flag now lives in the `FeatureFlags-iOS` package and maps to `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination`. PR 2 is final and awaiting review as [#6175](https://github.com/duckduckgo/apple-browsers/pull/6175) at `8d6d95438e`: it adds lifecycle-safe scheduling, prepared/retained-provider revalidation, the stable NTP render gate, all three host visibility/coverage/animation paths, weak lifecycle pruning, and exact feature-off regression coverage. `ADDING_PROMOS.md` describes the complete source-branch integration, including the remaining PR 3 accounting/observability work.

---

## 1. Bottom line

1. **The causal problem is real and current: in the last 12 months ~15 new promo surfaces shipped native and exactly 1 shipped via RMF** (What's New — which first had to build RMF's only modal path, `70e5be3ef0` #2421). Over the same window 8 commits extended RMF *matching attributes* — teams teach RMF to observe native state; they do not move promos into it (§4.1).
2. **Soft blockers dominate.** The recurring pattern: a new promo targets local state RMF has no attribute for → adding the attribute is release-gated anyway (`Mappers/JsonToRemoteMessageModelMapper.swift:415-424`) → once a client PR is unavoidable, teams build the whole promo natively. Authoring friction (separate repo, 11 silent-discard paths, zero author-facing failure feedback — §A.11 in `iteration_2_findings.md` context, verified §5 row 14) removes RMF's remaining appeal (§4.3).
3. **One hard structural ceiling: RMF holds exactly one `scheduled` message globally.** `markScheduledMessagesAsDone` has no surface filter and runs before every insert (`SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:470-488,506-518`). On iOS a scheduled What's New (`.modal`) starves the NTP card and vice versa; on macOS NTP and tab bar share the one slot. Any plan that needs two live RMF surfaces hits this first (§3 G2).
4. **The auto-dismiss dispute resolves in the DRI's favor on every contested specific**: floor is 1 day (`JsonToRemoteMessageModelMapper.swift:167` clamps `max($0,1)`; schema `minimum: 1`), it is opt-in (omitted → the card persists indefinitely, `RemoteMessagingStore.swift:282-289`), no impression-count dismissal exists anywhere in the package (zero grep hits), and an undismissed admitted card blocks modal admission by design (`iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift`). The macOS schema cannot even author the field. **Mandatory auto-dismiss is schema-enforceable today with no client change** — but 20 of 24 live iOS message objects would need the field added in the same PR (§3 G6, §6 R1).
5. **Frequency capping is not missing — it exists 18 times over**: all 8 previously claimed implementations verified (2 of them the queues' own central mechanisms) plus 10 more found before the search was capped, i.e. **≥16 per-feature reimplementations outside the two central ones** (e.g. `SubscriptionPromoViewModel.swift:189` literally comments its 28-day window as a *"fallback when PromoQueue is off"*). Caps/cooldown/priority are queue-shaped gaps; building them into RMF would duplicate the desktop queue's model (§2.2, §3 G3–G4).
6. **Both platforms independently built a coordination layer and made RMF a single minority participant**: macOS registers 10 promos of which 2 are RMF — and those are observation-only externals the queue cannot gate (`macOS/DuckDuckGo/Promotions/PromoService.swift:431-450`); iOS coordinates 7 modals of which 1 is RMF. RMF's de-facto role has converged on *content + targeting input*, not owner.
7. **Coordination coverage leaks on both platforms.** macOS: `showWinBackOfferIfNeeded()` runs unconditionally in `windowDidBecomeKey()` outside the `promoQueue` guard and win-back is not registered — the flag does not protect against it (`macOS/DuckDuckGo/MainWindow/MainViewController.swift:443-453`). iOS: the sync-recovery prompt presents from `viewDidAppear` before the coordinated pass (`iOS/DuckDuckGo/MainViewController.swift:834,1101`), and the VPN expired-entitlement alert can *evict* a live coordinated modal (`iOS/DuckDuckGo/MainViewController.swift:3726-3728`) (§3 G10).
8. **Measurement remains mostly render-time-only, per message.** RMF fires 13 pixel types on iOS, 6 on macOS; the desktop queue fires zero pixels of any kind. The completed iOS source branch adds two aggregate per-denial collision pixels for PR 3, but no system records eligibility delay or eligible-but-not-shown delivery loss (§3 G11).
9. **Recommendation shape (§6): fix content/authoring gaps in RMF** (mandatory auto-dismiss via schema, author-facing validation feedback, campaign start/end dates, one generic iOS remote sheet — hybrid-rendered, demand-gated because `.modal` has never carried a production campaign); **build arbitration gaps in the client queue layer** (caps, priority, pending-retry, delay telemetry — the desktop queue is the yardstick and itself lacks four of them); **leave event-triggered, consent-mutating, and system UI native** and register their visibility instead; **plug the three leaks now** — they are cheap and independent of the iteration-3 decision.

---

## 2. What RMF supports today

### 2.1 Capability inventory

Legend: ✓ supported end-to-end · ~ partial/restricted · ✗ missing. Config-repo paths are under `remote-messaging-config/`; the rest under the Apple checkout.

| Capability | iOS | macOS | Evidence |
|---|---|---|---|
| Templates | ✓ 6: `small`, `medium`, `big_single_action`, `big_two_action`, `promo_single_action`, `cards_list` | ~ 4: schema omits `promo_single_action` + `cards_list`; client rejects `promo_single_action` per-renderer | client `Model/JsonRemoteMessagingConfig.swift:141-148`; schemas `schemas/ios/schema.json:575-578`, `schemas/macos/schema.json:416-419`; macOS rejection `macOS/DuckDuckGo/RemoteMessaging/ActiveRemoteMessageModel.swift:227-237`, `macOS/DuckDuckGo/TabBar/ViewModel/TabBarRemoteMessageViewModel.swift:70` |
| Surfaces (defined) | 4-constant closed `OptionSet` (Int16 bitmask): `newTabPage`, `modal`, `dedicatedTab`, `tabBar` | same (shared) | `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:193-209` |
| Surfaces (effective) | NTP (all banner templates) + `.modal` consumed **only** by What's New | NTP + tab bar (survey-only); `cards_list`→`.dedicatedTab` is stored and **never fetched for display** | iOS `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:25-31`, sole `.modal` fetch `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:57`; macOS fetch excludes `.dedicatedTab` `ActiveRemoteMessageModel.swift:219-222`; repo-wide `.dedicatedTab` consumers: none (only the provider declaration `macOS/DuckDuckGo/RemoteMessaging/DefaultRemoteMessagingSurfacesProvider.swift:29`) |
| Surface control | App-decided allowlist. Config may declare `surfaces` but it is **intersected** with the compiled per-template set — config can narrow, never broaden; empty intersection silently drops the message | same | `Mappers/JsonToRemoteMessageModelMapper.swift:129-134,172-232`; hardcoded bypass exception: tab-bar shows a non-tab-bar message iff `id == "macos_permanent_survey_tab_bar"` (`TabBarRemoteMessageViewModel.swift:65-71`, `macOS/DuckDuckGo/TabBar/Model/TabBarRemoteMessage.swift:22`) |
| Scheduling | ✗ one `scheduled` message **globally**, all surfaces; surfaces filter reads only | same (shared store) | write path `RemoteMessagingStore.swift:470-488,506-518`; read filter `:244-269`; matcher emits ≤1 winner `RemoteMessagingConfigMatcher.swift:51-78` |
| Priority | ✗ JSON array order; `evaluate` ends in `.first`; no priority/severity field (0 grep hits) | same | `RemoteMessagingConfigMatcher.swift:52,77`; live proof: `25ab4c5` 2025-11-14 "Bump up macOS Duck.ai priority (#267)" is just a message moved to the top of the array |
| Pacing / caps / cooldown | ✗ none. Persisted state is `shown` bool + `firstShownDate` + status only | same | Core Data model `CoreData/RemoteMessaging.xcdatamodeld/RemoteMessaging 3.xcdatamodel/contents:3-10`; zero grep hits for cooldown/frequency/impression/cap in the package |
| Campaign start/end dates | ✗ none in schema or client; campaign windows are humans merging add/remove PRs (since 2025-07: iOS 59 config commits ≈ 19 adds + 21 removals) | same | schema grep zero hits (both schemas); commit history `remote-messaging-config` `live/ios-config/` |
| Per-user expiry (auto-dismiss) | ~ `displayConditions.dismissAfterDaysShown`: integer **days, min 1** (clamped), **opt-in**, enforced lazily at fetch time, dismissal is permanent | ✗ **not authorable** — macOS schema has no `DisplayConditions` at all (`additionalProperties: false` would reject it); shared client would honor it if present | mapper clamp `JsonToRemoteMessageModelMapper.swift:167`; enforcement `RemoteMessagingStore.swift:282-289`; schema `schemas/ios/schema.json` `DisplayConditions.dismissAfterDaysShown {integer, minimum: 1}`, not in any `required`; macOS schema: field absent. Landed: client `f3e4d699f7` 2026-05-12, iOS schema `aadb889` 2026-05-20 |
| Impression-count expiry | ✗ does not exist (no counter of any kind in the package) | same | greps `timesShown/shownCount/maxImpressions/impressionCount`: zero hits |
| Triggers | ~ `MessageTrigger` has exactly one case, `afterIdle`; used live by 2 messages | ✗ effective — macOS fetches with the default `.noTrigger` filter, so a triggered message can never show | enum `Model/RemoteMessageModel.swift:21-23`; default `RemoteMessagingStore.swift:244`; macOS fetch `ActiveRemoteMessageModel.swift:221`; live usage `live/ios-config/ios-config.json` (`ios_ntp_after_idle_*_2026`) |
| Targeting vocabulary | 44 recognized keys; **38 effective on iOS** (31 Apple-shared + 7 iOS-only) | **37 effective on macOS** (31 + 6) | mapper `JsonToRemoteMessageModelMapper.swift:24-69`; matchers `Matchers/UserAttributeMatcher.swift:117-138,213-234,318-396`, `Matchers/AppAttributeMatcher.swift:72-133`; macOS provider populates 37 real values `macOS/DuckDuckGo/RemoteMessaging/RemoteMessagingConfigMatcherProvider.swift:111-254` |
| New vocabulary | ✗ release-gated: unknown key → `UnknownMatchingAttribute` → rule's authored `fallback`; recognized-but-wrong-platform key → silent `.nextMessage` skip | same | `JsonToRemoteMessageModelMapper.swift:415-424`; `RemoteMessagingConfigMatcher.swift:88-99`; `UserAttributeMatcher.swift:392-394` |
| Schema/client drift | iOS schema admits 43/44 keys incl. **5 macOS-only keys that silently skip on iOS device** | macOS schema admits 39/44 incl. **2 iOS-only keys** (`syncEnabled`, `shouldShowWinBackOfferUrgencyMessage`) that silently skip — despite macOS running a live win-back campaign it cannot target | computed diff of `schemas/*/schema.json` `MatchingRule.attributes.properties` vs mapper list; macOS win-back exists (`macOS/.../WinBackOffer/WinBackOfferPromptPresenter.swift`) |
| Actions | ✓ 7 (`share`,`url`,`url_in_context`,`appstore`,`dismiss`,`survey`,`navigation`); 9 nav targets in client, iOS schema allows 8 | ~ same 7 actions; **macOS schema allows only 2 nav targets** (`feedback`, `softwareUpdate`) | client `Model/RemoteMessageModel.swift:356-378`; schemas `schemas/ios/schema.json:293-297`, `schemas/macos/schema.json:389-393` |
| Placeholders/icons | closed compiled set of 22; new icon = app release; iOS schema lists 20, macOS 13; JSON `PrivacyShield` silently renders the Subscription asset; unknown → `Announce` | same client set | `Model/JsonRemoteMessagingConfig.swift:160-183`, `Model/RemoteMessageModel.swift:380-403`; quirks `JsonToRemoteMessageModelMapper.swift:361-363,380-381,410-411` |
| Remote images | ✓ `imageUrl` on all templates except `small`; prefetch + dedicated URLCache (1MB/5MB) | ~ model accepts, **NTP renderer discards it** (pattern-matches `_`, icon enum only) | `Model/RemoteMessageModel.swift:257-297`; `RemoteMessagingImageProvider.swift:27-112`; macOS drop `macOS/LocalPackages/NewTabPage/Sources/NewTabPage/RMF/NewTabPageDataModel+RMF.swift:52-73`. Zero live usage on either platform today |
| Localization | ✓ inline JSON translations, exact-locale → language → English per-field fallback, applied before persistence | same | `JsonToRemoteMessageModelMapper.swift:154-156,440-455`; `Model/RemoteMessageModel.swift:101-190` |
| Experiments | ✓ `expVariant` + per-rule `targetPercentile` with sticky per-entity random percentile (also used live as an off-switch: `pct<0`) | same | `Matchers/AppAttributeMatcher.swift:128-129`; `RemoteMessagingConfigMatcher.swift:144-151`; `RemoteMessagingPercentileStoring.swift:26-52`; live `ios_pir_freemium_entry_point` rule 20 |
| Measurement | ~ 13 pixel types (shown/unique/dismiss+type/action×3/sheet/card×2/image×4), all render-time, per-message `isMetricsEnabled` gate | ~ strict subset: 6 | iOS `iOS/DuckDuckGo/Pixels/RemoteMessagingPixelReporter.swift:30-118`, `iOS/Core/PixelEvent.swift:861-873`; macOS `ActiveRemoteMessageModel.swift:166-213`, `macOS/DuckDuckGo/Statistics/GeneralPixel.swift:980-986`. **No eligible-not-shown/delay/suppression metric anywhere**; shared package fires zero pixels |
| Lifecycle | fetch every foreground + BG task ≥4h; re-evaluate only on new config version, invalidation, or evaluation >24h old; user dismissal is permanent and invalidates | macOS equivalent | `iOS/DuckDuckGo/AppServices/RemoteMessagingService.swift:116-149`; `iOS/DuckDuckGo/RemoteMessagingClient.swift:36-46,157-189`; `RemoteMessagingConfigProcessor.swift:55-85`; `RemoteMessagingStore.swift:351-375` |
| Kill / rollout | config removal (kill after next fetch), percentile gating, whole-framework privacy-config gate; per-PR staging URL + ajv CI validation (iOS/macOS only), auto-publish on merge | same | `.github/workflows/ios-PR-to-staging.yml`, `.github/scripts/validate-config.sh` (config repo); gate `RemoteMessagingAvailabilityProviding.swift:43` |
| Authoring aids | thin: 6-line schema READMEs, templates dir is stale Android-era (actions/attributes that don't exist on Apple), 4 iOS samples | — | `remote-messaging-config/templates/`, `samples/`, `schemas/*/README.md` |

**Live-config ground truth (what RMF actually carries):** iOS v121 — 24 message objects, 10 distinct IDs, 27 rules; 18/24 objects are surveys; only `medium`/`big_single_action`/`big_two_action` templates; **no modal/cards_list campaign has ever shipped on iOS**; no live remote image; 4 IDs use `dismissAfterDaysShown` (all `5`, all added May–Jul 2026). macOS v59 — 21 objects, 9 IDs, 25 rules; 15/21 surveys, rest update/EOL nags; zero `surfaces` fields, zero auto-dismiss (schema forbids). Windows live config: 4 messages; Android: 22 objects/8 IDs. `remote-messaging-config/live/*/`.

### 2.2 The two baselines: desktop promo queue vs RMF

The desktop queue (`macOS/DuckDuckGo/Promotions/`, created 2026-03-12 `2cb006f42a` #3811, flag `promoQueue` **default enabled**, `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift:741-742`) is the second capability yardstick. A gap the queue already solves is not an RMF gap.

**What the desktop queue has that RMF does not:**

| Queue capability | Detail | Evidence |
|---|---|---|
| Priority | registration-array order, deterministic | `PromoService.swift:489-510`; `Promo.swift:22` |
| Severity + coexistence | `low/medium/high`; two visible ≥medium block each other unless mutually coexisting; **low bypasses all rules** | `PromoTypes/PromoSeverity.swift:20-38`; `PromoService.swift:519,537-539` |
| Contexts | `global/newTabPage/webPage/fireWindow` conflict model | `PromoTypes/PromoContext.swift:20-26`; `PromoService.swift:528-535` |
| Initiated-kind global cooldowns | `.app` → 1/day, `.user` → 1/hour — measured from **last dismissal**, ≥medium only | `PromoTypes/PromoInitiated.swift:29-34`; `PromoService.swift:542-550` |
| Per-promo history | `timesDismissed`, `lastShown/lastDismissed`, `nextEligibleDate` (`.distantFuture` = permanent), `actioned` (never again) | `PromoTypes/PromoHistoryRecord.swift:21-53`; `PromoService.swift:656-678` |
| 19 UI treatments w/ per-type timeout | e.g. `featureTip` 5s→day cooldown, `dotBadge` 3d, `nudgeButton` 7d→permanent | `PromoTypes/PromoType.swift:54-158` |
| Safety gates | onboarding suppression; 5s external-activation suppression (discards buffered triggers) | `PromoService.swift:492,334-345,455-464` |
| Internal/external model + retraction | externals (incl. RMF) observed; conflicting internals retracted when an external appears | `Promo.swift:97-133`; `PromoService.swift:401-450` |
| Restore-on-launch | re-shows a promo visible at shutdown | `PromoService.swift:468-486` |
| Debug tooling + tests | force-show, undismiss, simulated date advance; 84 unit tests + UI tests | `PromoDebugMenu.swift:88-228`; `macOS/UnitTests/Promotions/` |

**What RMF has that the desktop queue does not:** remote content/copy/localization/images; 44-attribute targeting; remote kill and percentile rollout; campaign identity + per-message pixels; cross-message targeting (`messageShown`/`interactedWithMessage`). The queue carries zero content and **zero pixels** (grep: no matches in `Promotions/`), and its registry/metadata are compiled (`PromoServiceFactory.swift:60-79`).

**What both lack** (genuinely missing everywhere): impression caps; absolute campaign windows; pending/retry when a blocker clears (queue skips, `PromoService.swift:500-506,621-649`); delay/eligible-not-shown telemetry; essential-preemption flag; dynamic registration.

### 2.3 NTP surface states (requested gap-fill)

The NTP is not one surface. Three construction paths all receive the same messages config (`iOS/DuckDuckGo/MainViewController.swift:1976-1997`; `SuggestionTrayViewController.swift:474-495`; `UnifiedInputContentContainerViewController.swift:749-781`):

| NTP state | RMF card renders? | Coordination lease | State-specific promos |
|---|---|---|---|
| Standalone NTP | ✓ | plumbed, **not yet enforced** (status note above) | return-to-tab hatch when after-idle |
| Focused/omnibar NTP (suggestion tray) | ✓ same view, not gated on focus (`iOS/DuckDuckGo/NewTabPageView.swift:123,181,230-236`) | plumbed, not enforced | hatch forwarded |
| Duck.ai toggle (UTI) | ✗ no `NewTabPageView`; recents/logo only (`UnifiedSuggestionsContentResolver.swift:59-67`) | n/a — Duck.ai sync promo instead yields via the bespoke `wasModalPromptRecentlyPresented` check (`AIChatSyncPromoViewModel.swift:49-53`) | **Duck.ai sync promo lives only here** |
| Search toggle (UTI) | ✓ — an RMF message can even force the embedded NTP to appear (`hasFavorites \|\| hasMessages`, `UnifiedSuggestionsContentResolver.swift:53-56`) | plumbed, not enforced | hatch pinned to bar chrome |
| After-idle return | ✓ with priority for `after_idle`-triggered messages (`iOS/DuckDuckGo/HomePageConfiguration.swift:52-82`); targetable via `ntpAfterIdleState` attribute (landed `795491cbf1` 2026-06-26) | as underlying state | return-to-tab card (exclusive) |

---

## 3. The gaps

Ranked. **Shape**: RMF = belongs in RMF; Queue = belongs in the arbitration layer (desktop queue is the model); Neither = stays native. Release column: does closing it need an app release?

| # | Gap | What it blocks | Real example(s) | Shape | Effort / release |
|---|---|---|---|---|---|
| G1 | **No generic remote modal/sheet on iOS.** `.modal` is consumed only by What's New, whose `cards_list` template fits release notes, not hero/upsell/consent layouts; and it burns the message (shown+dismissed) at presentation (`WhatsNewRepository.swift:65-73`). What a new remote modal needs, precisely: the **surface constant already exists** (`RemoteMessageModel.swift:203`); missing are a **hero/upsell template** (schema + `JsonToRemoteMessageModelMapper`, release-gated) and a **renderer** (a native half-sheet consuming it) — two of the three pieces | Every modal promo: subscription reinstaller/existing-user sheets, win-back launch sheet, cookie opt-in (content), sync recovery | `SubscriptionPromoCoordinator.swift:76-88`; `WinBackOfferModalPromptProvider.swift:22-46` | RMF (content/template); rendering best hybrid-native | M–L, app release. **Demand-gate it**: `.modal` has never carried a live campaign (§2.1) |
| G2 | **Single global scheduled slot** — surfaces are not independent queues | Running any two RMF surfaces at once (What's New + NTP card on iOS; NTP + tab bar on macOS); any "RMF as the queue" ambition | store write path `RemoteMessagingStore.swift:470-488,506-518` | RMF (store/processor rework) | L, app release. Defer until a second concurrent surface is actually demanded |
| G3 | **No impression caps / re-show cooldowns / global pacing in RMF** | The pacing every capped promo had to hand-roll | VPN menu dot cap 4 (`FreeTrialBadgePersistor.swift:30-34`), cookie opt-in cap 3 (`CookiePopupProtectionOptInModalPromptProvider.swift:96`), Duck.ai sync cap 5 (`SyncPromoManager.swift:61`) — plus 13 more (§4.3) | **Queue** — initiated cooldowns + history exist in the desktop queue; caps do not exist anywhere yet | M in the queue layer; do **not** build in RMF |
| G4 | **No priority/severity/context model in RMF** (array order) | Cross-promo ordering; interruption budgeting | live "priority bump" = array reorder commit `25ab4c5` | **Queue** — desktop `PromoType`/`PromoSeverity`/`PromoContext` already model it | — (exists in queue); iOS adoption is iteration-3 scope |
| G5 | **No absolute campaign start/end dates** | Time-boxed campaigns without humans merging add/remove PRs at the boundary | Black Friday CTA is a privacy-config flag + hardcoded copy instead (`iOS/Core/FeatureFlag.swift:231,709-710`; `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/BlackFridayCampaignProvider.swift:45-71`); ~21 campaign-removal commits in 12 months | RMF (schema + client) | S–M, app release (new `displayConditions` fields) |
| G6 | **Auto-dismiss: opt-in, 1-day floor, iOS-schema-only** | Cards persisting indefinitely and (with the queue on) deferring launch modals every NTP foreground; hour-granularity campaigns; macOS authoring entirely | 20/24 live iOS objects have no `displayConditions`; blast-radius mechanism `PromoQueueLeaseArbiter.swift:172-173` + TECH_DESIGN rule 1 | RMF | Mandatory-at-authoring: **S, config-repo only** (add to `required` arrays; ajv CI enforces; retrofit 20 live objects in same PR). macOS schema parity: S. Sub-day granularity: S–M, app release |
| G7 | **Release-gated vocabulary + silent whole-message discard + no author feedback.** 11 distinct silent-drop paths (unknown template/action/nav target/survey param, empty copy, no eligible surface, invalid trigger, cards-list structure…), all debug-log-or-nothing; no pixel, no CI simulation of device matching; both schemas admit keys the target platform silently skips | Author confidence; every "why didn't my message show" investigation; makes native path feel safer | drop inventory `JsonToRemoteMessageModelMapper.swift:129-142,197-231,303-311,335-356,410-424,462-481,538-553`; schema-drift diff §2.1 | RMF (tooling/process) | M: validation-error pixel + schema/vocabulary sync check + authoring docs. Partly config-repo-only |
| G8 | **No event-driven evaluation** (fetch/24h cadence; one trigger case) | Promos keyed to a just-happened event: in-page import/extension sheets, email-protection signup, Duck Player pills, data-import sync footer | `TabViewController.swift:4597-4676`; `DataImportSummaryViewModel.swift:93-125` | **Neither** — keep eligibility native (hybrid: RMF supplies content/kill only where worth it) | L to generalize in RMF; not recommended |
| G9 | **No native-surface bridge** (headers, chrome bars, menu dots, badges, settings rows) | The 12 class-(b) candidates from `iteration_2_findings.md` §B.3; the passwords-header private queue | 4-way chain `AutofillLoginListViewController.swift:746-795`; sync promos ×4; PIR badge; home-row banner | Hybrid: **Queue** owns visibility; RMF-shaped only for content/kill per candidate | M foundation + S per promo (unchanged from prior analysis) |
| G10 | **Coordination coverage leaks** — arbiter sees only RMF (`PromoType` has one case, `PromoQueueLeaseArbiter.swift:22-23`); uncoordinated presents on both platforms | Queue-on still collides | macOS win-back (`MainViewController.swift:443-453`, unregistered, real `beginSheet` — `WinBackOfferPromptPresenter.swift:45-49`, `ModalView.swift:26-43`); macOS bookmarks-bar prompt (`:460-479`); iOS sync recovery (`MainViewController.swift:834`); iOS VPN alert ×2 paths, one of which dismisses the presented VC (`VPNService.swift:96-100`; `MainViewController.swift:3714-3741`) | **Queue** | S each to register/guard; independent of iteration 3 |
| G11 | **No delay/eligible-not-shown measurement** | The §7 measurement dispute cannot be settled with delivery-loss data | RMF render-only pixels (§2.1); desktop queue zero pixels; the completed iOS source branch adds two aggregate collision-denial pixels in `prompt-coordination.json5` for PR 3, but no delay duration or owner-attributed delivery signal | Both (new capability, queue-adjacent) | M + measurement review |
| G12 | **macOS parity holes** | promo-style NTP campaigns on macOS; consistent cross-platform authoring | `promo_single_action` unsupported (`ActiveRemoteMessageModel.swift:227-237`); NTP renderer ignores `imageUrl` (`NewTabPageDataModel+RMF.swift:52-73`); 2 nav targets; no `DisplayConditions`; matcher can't target `winBackOfferUrgency` | RMF | S each, app release (except schema items) |

Hygiene finding, not a gap: `.dedicatedTab` has no consumer on any platform — a macOS `cards_list` message would persist invisibly. Either delete the constant or stop mapping `cards_list` to it (`macOS/DuckDuckGo/RemoteMessaging/DefaultRemoteMessagingSurfacesProvider.swift:29`). The tab-bar ID escape hatch (§2.1) is evidence the closed surface model has already been bypassed once rather than extended.

---

## 4. Why new promos land outside RMF

### 4.1 The 12-month record (2025-07-30 → 2026-07-30)

Every promo-relevant iOS landing, with the path chosen (full sweep; commits cited in Appendix A):

| Landed | Promo | Path | Blocker class |
|---|---|---|---|
| 2025-09-01 | Inactivity retention notification | Native (UNNotification) | hard: no notification surface |
| 2025-09-09 | Address-bar picker force-choice | Native | hard: writes a setting, undismissable |
| 2025-09-22 | Sync recovery prompt | Native, uncoordinated | soft: local keychain state → attribute would need release |
| 2025-10-09→11-07 | **Win-back offer** | **Split**: launch modal native; day-3/4 urgency banner **via RMF attribute** `shouldShowWinBackOfferUrgencyMessage` (`iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:121`) | the microcosm — RMF used exactly where a surface already existed (NTP), native where none did (modal) |
| 2025-11-05 | Modal prompt coordination itself (#2337) | Native infrastructure | built *because* native modals were colliding |
| 2025-11-07 | **What's New** | **RMF** — the one new RMF promo; required building `.modal` consumption first | — |
| 2025-11-24 | Autofill-extension promo (sheet + header) | Native | hard(sheet): in-page event; soft(header): no surface |
| 2025-12-12 | App-rating remote kill flag | Native (StoreKit) | hard: system UI |
| 2026-01-15 | Data-import sync promo footer | Native | hard-ish: end-of-import event timing |
| 2026-02-06 | PIR `NEW` badge | Native | soft: badge surface + version-window state |
| 2026-02-23→03-04 | Return-to-tab / after-idle hatch | Native (utility) + new RMF **attribute** `ntpAfterIdleState` later | — |
| 2026-03-23 | Subscription promo (reinstallers) | Native, coordinated provider | soft: `variant`/`hasSkippedOnboarding` attributes missing → release either way |
| 2026-04-07 | **Fire Mode promos** (NTP card + menu + tip) | Native → capped 2026-05-26 → **disabled + deleted 2026-07-02** (`28adcfb43e`, `192a021c0a`); coordinator survives hardcoded `return false` (`FireModePromotionsCoordinator.swift:121-123,146-147`), not in pbxproj | soft: whole ship→cap→kill lifecycle consumed app releases; RMF would have made the NTP-card half config-only |
| 2026-05-14 | Duck.ai picker upsell | Native (tap-response paywall) | excluded: transactional |
| 2026-05-22→07-28 | Duck.ai sync promo card (cap 3, intro sheet; sheet removed + cap→5 on pixel evidence `c7ea453fcf` #6025) | Native, with a bespoke one-off yield check (#5625) | soft: switch-bar surface + chat-count state |
| 2026-07-06 | Cookie pop-up protection opt-in | Native, coordinated provider | hard: writes `cookiePopupPreference = .max` + present-time experiment enrollment (`CookiePopupProtectionOptInModalPromptProvider.swift:116-121,188-193`) |
| 2026-07-08 | Free-trial expiration reminder notification | Native (web-scheduled UNNotification) | hard: notification + web-supplied timing |
| 2026-07-17 | Subscription promo (existing users) | Native, coordinated provider | soft/hard mix: live onboarding-dialog visibility check at presentation |
| 2026-07-27 | Monthly free-trial experiment | Native — PR title says "**Native implementation** …" (#5996) | hard: StoreKit SKU filtering |
| 2026-07-27 | Next Steps dismissability rework | Native | — |

Same-window RMF activity: 8 commits adding **attributes/capabilities** (`subscriptionFreeTrialActive`, `pproSubscriptionTier`, `ntpAfterIdleState`, navigation action, auto-dismiss, card styling…), i.e. RMF grew as a *targeting/observation* system, not as a promo carrier. Config-repo authoring stayed healthy (59 iOS commits) — the bottleneck is not author appetite.

### 4.2 Hard blockers (RMF structurally cannot)

OS notifications; StoreKit (rating request, SKU sets); consent/setting mutations (cookie `.max`, address-bar choice); real-time page/event triggers (form-fill, post-login, import-completion — RMF evaluates on fetch/24h, `RemoteMessagingConfigProcessor.swift:55-85`); live-UI presentation checks (`isShowingContextualOnboardingDialog`); experiment enrollment at presentation time.

### 4.3 Soft blockers (the actionable finding)

These are the reasons RMF loses when it *could* have carried the promo:

1. **The surface gap makes RMF a non-starter for 90% of promo shapes.** Effective iOS RMF = NTP card + one bespoke release-notes modal. Every header, sheet, pill, badge, bar, and settings row is out of scope before the conversation starts. Teams don't evaluate RMF and reject it; there is nothing to evaluate.
2. **Release-gating erases RMF's speed advantage exactly when it matters.** New promos overwhelmingly target local state (churn dates, vault counts, install variant, provider enablement). The attribute doesn't exist → client release required → "config-only" is off the table → build the whole thing natively and keep control. The win-back split (§4.1) proves teams *will* use RMF when the marginal cost is one attribute on an existing surface.
3. **Authoring is unattractive even when possible**: separate repo, 11 silent-discard paths with no author-facing signal (G7), schemas that accept rules the device will silently skip, stale templates, 6-line docs. The observed workaround culture (percentile `<0` as an off-switch; the hardcoded tab-bar ID bypass) shows authors route around the model rather than extend it.
4. **RMF wouldn't have saved the work teams actually dread.** What promo authors keep rebuilding is pacing and mutual exclusion — 18 independent frequency-cap/cooldown implementations were located and verified, of which 2 are the centralized queue mechanisms (`PromoHistoryStore`, `PromptCooldownManager`) and **≥16 are per-feature reimplementations**: the 6 remaining previously-believed sites all verified (`FreeTrialBadgePersistor` max 4, `SubscriptionPromoViewModel` 28d/4-show with its *"fallback when PromoQueue is off"* comment at `SubscriptionPromoViewModel.swift:189`, `BrokenSitePromptLimiter` 3-streak/30d/7d, `VPNUpsellUserDefaultsPersistor` 7d, `AutofillExtensionPromotionManager` max 5, `NewBadgeVisibilityManager` 7d/3 releases) plus 10 more found before the search was capped (win-back 270d, app rating, address-bar picker, macOS Next Steps 1-dismiss/5-show, credentials-import max 5, Fire Mode, macOS default-browser ladder, macOS sync-device buttons 5/7d, Duck Player 3-dismiss toast, Quick Feedback 24h/7d). RMF has none of this (G3), so migrating content still leaves the hard part. Hand-rolled *arbitration* shows the same pattern: `QuitSurveyDecider.noOtherDialogsWillShow` knows a hardcoded list of exactly two other dialogs (`macOS/DuckDuckGo/QuitSurvey/QuitSurveyDecider.swift:114-117`), the autoconsent popover runs an 8-condition self-check outside the queue (`AutoconsentStatsPopoverCoordinator.swift:77-92`), the passwords screen runs its own 4-way session-scoped queue, and the Duck.ai sync promo got a one-off `wasModalPromptRecentlyPresented` yield (#5625 — PR body: the two systems "had no awareness of each other, so both could fire in the same session").
5. **No enforcement moment.** Nothing in review asks "why not RMF / which queue slot": promos ship uncoordinated (sync recovery presents from `viewDidAppear` before the coordination pass even runs; the coordination service then silently skips all providers via its `presentedViewController` guard, `PromoCoordinationService.swift` — no retry), and a PR can title itself "Native implementation" without friction.

**Trend: not improving on the dimension that matters.** RMF's targeting role is growing (8 attribute commits), its carrier role is flat (one new consumer in 12 months; the modal surface built for it has never carried a production campaign), and native promo shipping cadence is high (~15). Absent intervention, iteration 2's default outcome is more attributes, zero new RMF-carried promos.

---

## 5. Perceived vs real gaps

| Belief held on the project | Verdict | Evidence |
|---|---|---|
| RMF keeps one scheduled message globally; a scheduled modal starves the NTP | **Real** | `RemoteMessagingStore.swift:470-488,506-518`; matcher single winner `RemoteMessagingConfigMatcher.swift:77` |
| No priority field; JSON order decides | **Real** | `.first`; live "priority bump" commit = array move (`25ab4c5`) |
| No cooldown/caps/pacing/absolute dates in RMF | **Real** | zero grep hits; Core Data model has `shown`+`firstShownDate` only |
| "Shortest auto-dismiss is 1d, no hour/minute options; opt-in; omitted → persists indefinitely" (DRI) | **Real, exactly** | `max($0,1)` clamp `JsonToRemoteMessageModelMapper.swift:167`; `Int?` days; schema `minimum: 1`, not required; enforcement `RemoteMessagingStore.swift:282-289` |
| "We already support `dismissAfterDaysShown`… basic auto-dismiss is in place" (advisor/Android DRI) | **True but non-responsive** | the mechanism exists (since 2026-05-12) — none of the three contested specifics were wrong; also iOS-schema-only |
| Impression-count auto-dismiss exists somewhere | **False** | no counter anywhere in the package (grep) |
| An undismissed RMF card defers launch modals on every foreground where it renders (DRI) | **Real by design** (queue on) | `acquireModalLease` fails while any visible-promo lease exists in `PromoQueueLeaseArbiter.swift`; reconsidered next foreground (TECH_DESIGN rule 1). Bounded by dismissal/`dismissAfterDaysShown`/config change. The final PR 2 stack wires the lease through all three NTP hosts. |
| Remotely-controlled "max times shown" is being brought over (advisor) | **Not yet in code or schema** | no such field in either repo — **reported (Asana), not code-verifiable** as a plan |
| Iteration-1 cooldowns are hardcoded / are remote (contradictory statements) | **Both half-right** | remote-tunable `promptCooldownInterval` (hours) from privacy-config `.iOSBrowserConfig`, hardcoded default 24h (`PromptCooldownIntervalProvider.swift:29-62`) |
| `cards_list` works on macOS via dedicated tab | **False** | mapped to `.dedicatedTab` (`DefaultRemoteMessagingSurfacesProvider.swift:29`) which no fetch/renderer consumes; message persists invisibly |
| The iOS modal path is used in production | **False** | live iOS config v121 has never carried a modal/cards_list campaign |
| New matching attributes are config-only changes | **False** | release-gated; unknown keys → authored fallback (`JsonToRemoteMessageModelMapper.swift:415-424`) |
| iOS schema is missing `pproSubscriptionTier`/`ntpAfterIdleState` (prior docs) | **Fixed since** | both present now; remaining drift is cross-platform key admission (§2.1) |
| Frequency capping is missing from the codebase | **False — rebuilt ≥16×** | §4.3 item 4 |
| macOS promo queue is a shared package mobile can adopt | **False** | app-target code, `macOS/DuckDuckGo/Promotions/` (nothing under SharedPackages) |
| Enabling the macOS queue flag prevents promo collisions | **False** | win-back sheet fires outside it, unregistered (`MainViewController.swift:443-453`) |
| The app controls the rating prompt | **Half** | app controls the *ask* (2 lifetime asks: day-3 + day-7 unique-usage, Core Data `AppRatingPromptEntity`, `iOS/DuckDuckGo/AppRatingPrompt.swift:54-82`; remote kill exists via `appRatingPrompt` flag) — `SKStoreReviewController.requestReview(in:)` (`TabViewController.swift:2053`) gives iOS final say, no display callback, system 3/365d cap |
| Fire Mode promos still exist (count them?) | **Dead 3 ways** | eligibility hardcoded `false`, file out of pbxproj, references a type that no longer exists (`FireModePromotionsCoordinator.swift:113-123,146-148`) |
| Duck.ai sync promo caps at 3 | **Stale** — now 5 | raised 2026-07-28 `c7ea453fcf` #6025 (`SyncPromoManager.swift:61`) |

---

## 6. Recommendation

**Frame:** RMF is a good remote-content/targeting/kill system with an authoring-experience problem and a one-slot scheduler; it is not, and should not become, the arbiter. The desktop queue is a good arbiter with no remote-policy plane and no content. Iteration 2 should close RMF-shaped gaps in RMF, queue-shaped gaps in the coordination layer, and stop pretending the third category (events/consent/system UI) is migratable.

| # | Action | Where | Effort / release | Why now |
|---|---|---|---|---|
| R1 | **Make auto-dismiss mandatory at authoring** (iOS): add `displayConditions` + `dismissAfterDaysShown` to the schema `required` arrays; retrofit the 20 live objects in the same PR (ajv CI enforces atomically). Add `DisplayConditions` to the macOS schema. Decide policy for evergreen surveys explicitly (they are 18/24 of live objects) | config repo only | **S, no app release** | Validates the project lead's proposal — it is mechanically enforceable today; closes the indefinite-persistence half of G6 |
| R2 | **Author-facing failure feedback**: a validation-error pixel (client) + a CI step that runs the device mapper rules against the PR config (catches wrong-platform keys, silent drops) + refresh templates/docs | RMF client + config repo | M (pixel is release-gated; CI is not) | G7 is the biggest soft blocker that is cheap to attack |
| R3 | **Campaign start/end dates** in `displayConditions` | RMF schema + client | S–M, app release | G5; removes ~40 human add/remove commits a year and the Black Friday flag pattern |
| R4 | **Plug the leaks** (independent of iteration 3): register macOS win-back in the queue (or guard it); route iOS sync-recovery through the coordination service; fix the VPN-alert eviction path | app code | S each, app release | G10; these are live collision paths the current flags don't cover |
| R5 | **One generic remote sheet for iOS, hybrid-rendered** (RMF schedules/targets/kills; a native half-sheet renders), prototype = subscription-promo family per `iteration_2_findings.md` Wave 3 | RMF template + iOS renderer | M–L, app release | G1 — but **demand-gate it**: require a named campaign owner first, because the existing modal surface has never been used in production |
| R6 | **Do not build caps/priority/severity/pacing into RMF.** Put impression caps, pending-retry, and delay telemetry into the queue layer (they are the three things *neither* system has) — in whichever owner iteration 3 picks | queue layer | M | G3/G4/G11; avoids duplicating the desktop model and pre-empting iteration 3 |
| R7 | Defer the multi-slot store rework (G2) until a second concurrent RMF surface has a named use case | — | L | highest-cost, lowest-evidenced gap |
| R8 | Hygiene: remove or repurpose `.dedicatedTab`; delete the dead Fire Mode coordinator and Duck Player priming modal (orphaned keys incl. a typo'd one, `UserDefaultsPropertyWrapper.swift:182-183`); retire the tab-bar ID escape hatch when the survey ends | app code | S | keeps the surface model honest |

**On the Android DRI's proposal** (*"list all potential prompts, and have them become either an RMF ntp_card, or a modal"*): the inventory does not support it as a complete answer. Of ~35 active iOS promo units (Appendix A), roughly 9 are modal-shaped and 2 already NTP-card-shaped; **≥18 are headers, pills, badges, menu ornaments, settings rows, or notifications whose placement is the product intent** — funnelling them to NTP/modal changes what they are. It *is* a reasonable simplification for the high-interruption tier (the 7 coordinated modals + 2 uncoordinated sheets), and even there the single-slot scheduler (G2) and event timing (G8) still require a client arbitration layer. Partially adopt: use it as the default question for *new* interruptive promos, not as a migration plan.

**Where this leaves the premise:** "RMF should become the default for new promos" is supportable only for *remote-content, non-event, NTP-or-modal* promos — historically about a third of what ships. The defensible iteration-2 goal is narrower and stronger: **make RMF the default for content and kill, make the queue the default for visibility, and make bespoke-and-unregistered the exception that needs justification.** That matches the desktop lead's requested framing (requirements vs. what desktop doesn't support — §2.2 supplies both halves).

---

## 7. Open questions for humans

1. **Measurement scope** — project lead: in scope (*"otherwise we're blind"*); advisor: *"nice to have"*, not a release blocker; Android DRI: impacts delivery. All **reported (Asana)**. Facts to argue against: RMF already gives per-message shown/unique/dismiss/action (13 iOS pixel types); the source branch implements aggregate per-denial collision counting for PR 3, but nothing measures delay duration or eligible-not-shown delivery loss. Booked to a midmortem.
2. **Mandatory auto-dismiss policy** (R1): does product accept forced expiry on evergreen surveys (18/24 live objects), or should the requirement be per-template? Who owns the live-config retrofit PR?
3. **Does any campaign need two concurrent RMF surfaces** (e.g. a What's New while an NTP card runs)? Decides whether G2 is ever funded.
4. **Who is the named owner of a first remote-modal campaign** (R5's demand gate)? If nobody claims one in a quarter, G1 drops below G7 in priority.
5. **Global priority across NTP cards and modals** — the Android DRI's unanswered question (*"high risk, non-trivial… not sure if we need to go this far"* — **reported (Asana)**). The inventory answer in §6 covers his alternative; the remaining product question is whether small-surface promos (pills/badges/headers) must participate in one budget or only the interruption tier.
6. **App-rating prompt**: the queue can own *when the app asks* (the `requestReview` call and its Core Data eligibility) and nothing else — iOS owns display. Project lead calls it a key annoyance offender; Android DRI wants it in the coordinator — both **reported (Asana)**. Decide whether "asked" should consume a queue slot/cooldown even though display is unobservable.
7. **RMF vs. desktop queue as the long-term owner** — explicitly iteration 3's decision; this analysis feeds it and deliberately does not pre-empt it.
8. **Essential-message contract**: the VPN expired-entitlement alert must preempt and must never inherit promo cooldown — today it does so by racing and evicting (§3 G10). Who defines the essential class and its rules?

---

## Appendix A — iOS promo inventory (verified)

Four-part promo test applied: persuasive purpose · app-inserted · droppable · contends for a shared surface. **Coord** = participates in ModalPromptCoordination. Reason codes: NS = needs new surface, LS = needs local-state attribute, EV = needs immediate event trigger, CU = needs custom/consent UI, SYS = system UI, SOFT = RMF could plausibly have carried it.

### A.1 Coordinated launch modals (provider order = priority, `PromoCoordinationService.swift`)

| # | Promo | Files | Gating | Pacing (keys) | RMF | Landed | Why not RMF |
|---|---|---|---|---|---|---|---|
| 1 | Win-back offer sheet | `WinBackOfferModalPromptProvider.swift:22-46`; `WinBackOfferVisibilityManager.swift:111-122` | `winBackOffer` flag; churned ≥3d, not redeemed | once-ever keychain `offerPresentationDate`; 5d offer window; 270d re-churn cooldown | modal no; **urgency banner yes** (attribute) | 2025-10/11 | LS (keychain churn state) + NS; SOFT for content |
| 2 | Subscription promo (reinstallers) | `SubscriptionPromoCoordinator.swift:76-88,132-140` | `subscriptionPromoForReinstallers` + `privacyProOnboardingPromotion`; returning variant + skipped onboarding + ≥7d | once-ever `com.duckduckgo.ios.daxPrivacyProPromotionDialogShown` (shared with A.3-6) | no | 2026-03-23 | LS (variant/skip state); SOFT |
| 3 | Subscription promo (existing users) | `SubscriptionPromoExistingUserCoordinator.swift:70-93` | `subscriptionPromoForExistingUsers`; ≥7d; not reinstaller case | same shared once-ever key | no | 2026-07-17 | LS + live onboarding-dialog visibility check at presentation |
| 4 | Address-bar picker | `NewAddressBarPickerModalPromptProvider.swift:24-76`; validator `:70-103` | `showAIChatAddressBarChoiceScreen`; ≥1d install | once-ever `aichat.storage.newAddressBarPickerShown.v2` | no | 2025-09-09 | CU (forced choice, writes setting, undismissable) |
| 5 | Default browser (active + inactive) | `DefaultBrowserModalPromptProvider.swift:23-38`; decider `DefaultBrowserPromptTypeDecider.swift:164-170` | privacy-config `.setAsDefaultAndAddToDock` settings (delays 1/4/14d; inactive 28d/7d) | `com.duckduckgo.defaultBrowserPrompt.*` (lastShown/occurrences/permanentlyDismissed/inactiveShown) | no | 2025-07-01 | LS (activity ledger, isDefault API) + CU (inactive full-screen) |
| 6 | What's New | `WhatsNewModalPromptProvider.swift:27-111`; `WhatsNewRepository.swift:56-57` | presence of scheduled RMF `.modal` message (no app flag) | RMF-owned; burned shown+dismissed at presentation; replay via `com.duckduckgo.whatsNew.lastShownMessage` | **yes** | 2025-11-07 | — (is RMF) |
| 7 | Cookie pop-up protection opt-in | `CookiePopupProtectionOptInModalPromptProvider.swift:29-194` | 2 flags + A/B holdback cohort at present-time; ≥2d install | cap 3 `…optIn.shownCount`; never after confirm | no | 2026-07-06 | CU (writes `cookiePopupPreference = .max`) + experiment enrollment |

### A.2 Uncoordinated modals/sheets (all bypass the coordination service)

| Promo | Files | Trigger/gating | Pacing | Landed | Why not RMF |
|---|---|---|---|---|---|
| Sync recovery prompt | present `SyncRecoveryPromptPresenter.swift:80` from `MainViewController.swift:834` (`viewDidAppear` — runs before the coordinated pass); guards `SyncRecoveryPromptService.swift:62-98` | `newDeviceSyncPrompt` (default enabled); sync off; former-autofill heuristic; vault empty (async) | once-ever latch `com.duckduckgo.syncrecovery.check.performed` (burned before all guards pass) | 2025-09-22 | LS (async keychain state); SOFT for content — the leak is the finding |
| Password-import sheet (in-browser) | `TabViewController.swift:4597-4645`; `AutofillCredentialsImportPresentationManager.swift:77-128` | autofill event on login form; `canPromoteImportPasswordsInBrowser`; iOS 18.2+; <25 creds | cap 5 `…credentialsImportPromptPresentationCount` | 2025-07-22 | EV |
| Autofill-extension sheet (in-browser) | `TabViewController.swift:4647-4676`; `AutofillExtensionPromotionManager.swift:119-158` | post-fill login navigation; iOS 18+; extension off | cap 5 `…browser.presentationCount`; remote thresholds 7d/4 creds | 2025-11-24 | EV + system extension state |
| Email Protection in-context signup | `MainViewController+Email.swift:104-133` | page JS callback; `incontextSignup`; English | permanent-dismiss epoch `Autofill.InContextEmailSignup.dismissed.permanently.at` | pre-monorepo | EV |
| Onboarding subscription Dax dialog | `DaxDialogs.swift:686-692`; `NewTabDaxDialogFactory.swift:275-327` | onboarding chain; `privacyProOnboardingPromotion` | shared once-ever key (A.1-2/3) | 2025-05-09 | NS (onboarding state machine) |
| App-rating prompt | `AppRatingPrompt.swift:54-82`; `TabViewController.swift:2048-2055` | every DDG-SERP load once eligible; `appRatingPrompt` flag (remote kill exists) | Core Data: ask at 3rd + 7th unique-usage day, 2 lifetime asks; iOS decides display (3/365d system cap, no callback) | pre-monorepo (flag 2025-12-12) | SYS |
| Duck Player priming modal | `DuckPlayerPrimingModalView.swift` | **dead** — call site deleted 2025-05-07; replaced by welcome pill | orphaned keys (one typo'd) | dead | — |

### A.3 Headers, cards, pills, badges, settings

| Promo | Surface | Files | Pacing | Landed | Why not RMF |
|---|---|---|---|---|---|
| Passwords-header chain (import → survey → sync → extension) | passwords list header — **a private 4-way queue with session memory**; dismissing a higher promo does *not* promote the next this session | `AutofillLoginListViewController.swift:746-795` (session bools `:155-159`) | per-slot one-shot dismiss keys; extension slot remote thresholds | base pre-monorepo; extension slot 2025-11-24 | NS + LS; the private ordering is the finding |
| Sync promos ×4 (bookmarks / passwords / data-import / Duck.ai) | list headers, import footer, Duck.ai switch-bar | `SyncPromoManager.swift:100-139`; `AIChatSyncPromoViewModel.swift:49-65` | one-shot dismiss keys; **only Duck.ai has an impression cap (5**, raised from 3 2026-07-28); Duck.ai yields via `wasModalPromptRecentlyPresented` | bookmarks/passwords pre-monorepo; import 2026-01-15; Duck.ai 2026-05-22 | NS + LS (sync auth, counts); import variant EV |
| Home-row / add-to-home-screen reminder | chrome notification bar | `HomeRowReminder.swift:32-79`; `MainViewController.swift:3228-3243` | once-ever after >3d; **no remote kill flag**; effectively iPad-only (iPhone sees Add-to-Dock in onboarding) | © 2018 | NS; SOFT — oldest unkillable promo in the app |
| VPN menu free-trial dot | browsing-menu row ornament | `VPNSubscriptionPromotionHelper.swift:96-126`; `FreeTrialBadgePersistor.swift:30-64` | cap 4 `vpn-menu-item.free-trial-badge.view-count` | 2025-09/10 | NS (menu ornament) |
| PIR `NEW` badge | settings row badge | `NewBadgeVisibilityManager.swift:48-51,78-98` | 7d from first impression AND ≤3 minor releases (`firstImpressionDatePIRNewBadge`) | 2026-02-06 | NS + version-window state |
| VPN TipKit tips ×3 (geoswitch → widget → snooze) | VPN status screen inline | `VPNTipsModel.swift:78-127` | TipKit store; hand-rolled sequencing via `isDistancedFromPreviousTip` | © 2024 | EV (live VPN state) + TipKit |
| Duck Player welcome pill + toast | web-view-anchored pill | `DuckPlayerNativeUIPresenter.swift:467-482,601-616,769-827` | toast at exactly 3 user dismissals, once ever; counter resets on use while <3 | 2025-03/05 | EV (YouTube navigation) |
| Settings: Complete Setup | 2 swipe-dismissable rows (iOS 18.2+) | `SettingsCompleteSetupView.swift`; `SettingsViewModel.swift:1320-1373` | per-row dismiss keys; auto-dismiss at ≥25 passwords / once isDefault confirms | 2025-06-16 | LS (system checks) — Settings IA |
| Settings: Next Steps | 4 conditional rows + Hide | `SettingsNextStepsView.swift`; `SettingsViewModel.swift:1473-1541` | rows auto-dismiss 24h after tap; section Hide only ≥14d post-install | rework 2026-07-27 | Settings IA |
| Settings: subscription/win-back rows + **Black Friday CTA** | row CTA text swaps | `SettingsSubscriptionView.swift:96-133,277-305`; BF: `BlackFridayCampaignProvider.swift:45-71`, `SettingsViewModel.swift:235-251` | win-back rows track the 5d offer window; BF is a remote flag + `discountPercent` setting | 2025-10/11 | LS (StoreKit); BF = the campaign-dates gap (G5) worked around in privacy config |
| Fire Mode promos (NTP card, menu, tip) | — | `FireModePromotionsCoordinator.swift:121-123,146-148` | **dead**: hardcoded ineligible, out of pbxproj, dangling type refs | 2026-04-07 → killed 2026-07-02 | poster child for §4.1 |

### A.4 Out-of-app + borderline (tracked, not promo-classified)

| Item | Class | Files | Note |
|---|---|---|---|
| Inactivity retention notification | promo (out-of-app) | `InactivityNotificationSchedulerService.swift:26-144` | provisional-auth only; remote `daysInactive` (default 7); re-armed every foreground |
| Free-trial expiration reminder | promo (out-of-app) | `SubscriptionExpirationReminderScheduler.swift:38-186` | timing supplied by the subscription web page; its tap-segue can collide with a coordinated modal |
| Duck.ai picker upsell | excluded: transactional (user-initiated paywall) | `DuckAISubscriptionUpsellPresenter.swift:27-126` | no cap/persistence — fires every gated tap |
| Monthly free-trial experiment | excluded: paywall modification, no surface | `MonthlyFreeTrialExperiment.swift:25-35`; SKU filter `StorePurchaseManager.swift:272` | "Native implementation" by PR title (#5996) |
| VPN expired-entitlement alert | **collision-capable essential** — must preempt, must never inherit promo cooldown | `VPNService.swift:84-101`; duplicate path `MainViewController.swift:3714-3741` | two uncoordinated paths; one dismisses the presented VC (can evict a coordinated modal) |
| Return-to-tab card | collision-capable utility | `IdleReturnEligibilityManager.swift`; `EscapeHatchView` | exports `ntpAfterIdleState` to RMF |
| Broken-site prompt | collision-capable reactive utility | `BrokenSitePromptLimiter.swift:57-97` | remote-tunable 3-streak/30d/7d limiter — yet another pacing reimplementation |
| Onboarding, sync error/paused alerts, crash-collection consent, JS alerts, SaveLogin | collision-capable non-promos | A1 leak sweep (§3 G10) | several present via dismiss-and-replace and can steal the modal slot |

## Appendix B — macOS promo census (light, supports §2.2/§4)

Queue-registered (10, order = priority; `PromoServiceFactory.swift:60-79`): `session-restore`(ext), `remote-message-ntp`(**RMF**, ext), `freemium-dbp-ntp-banner`(int), `remote-message-tabbar`(**RMF**, ext), `next-steps-cards`(ext), `subscription-promo-fire-window`(ext), `default-browser-and-dock-popover/banner/inactive-modal`(int ×3), `cookie-popup-protection-opt-in`(int). RMF participation is observation-only: the queue never gates RMF, it reacts to it (`RemoteMessagePromoDelegate.swift:26-81`; `PromoService.swift:431-450`).

Existing but **unregistered** (all verified, none RMF): win-back ×4 surfaces (launch sheet — the live leak, NTP urgency banner, menu badge, Preferences sidebar badge); VPN upsell popover + auto-pin + dot; autoconsent stats popover (8-condition self-check); first-run Quit Survey (`noOtherDialogsWillShow` knows exactly 2 dialogs); Duck.ai TRY-FOR-FREE badges + omnibar upsell dialogs ×2; sync promos (bookmarks/passwords/autofill prefs) + sync-device buttons (caps 5 / 7d); autofill credentials-import promo + toolbar onboarding popover; Quick Feedback tip (24h/7d cooldowns); Black Friday CTA; onboarding Chrome-extension promo; DuckPlayer onboarding modal; update-available popover; broken-site prompt; tab-crash popover; bookmarks-bar prompt. Legacy Continue Set Up cards: removed (persistor remnant only).

Score: **~26 live promo-like surfaces, 10 registered (2 RMF)** — the macOS queue governs the launch-adjacent tier and observes RMF; the long tail self-arbitrates, exactly like iOS.
