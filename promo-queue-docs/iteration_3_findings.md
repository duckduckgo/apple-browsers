# Iteration 3 findings — which system should own the promo queue?

**Decision pre-read · verified 10 July 2026**

**Apple checkout:** `62280e48fa` on `bartosz/promo-queue` (docs-only commit on product-code baseline `c48ee2b6cf`)

**RMF config checkout:** `9ab24a7` on `bartosz/promo-queue`

This report answers iteration-3 RQ1–RQ5. It consumes the code-verified Program A inventory and evaluates four named choices: **A** (RMF becomes the queue), **B** (client queue; RMF is an input), **C** (layered: RMF schedules campaigns; the queue arbitrates visibility), and **B+** (B with bounded remote queue policy).

> **Source rule.** Stakeholder positions, Windows/Android status, product requirements, and the Android Fire Mode precedent are **reported (Asana), not code-verifiable** and cite the local research digests. Code and config claims cite the current checkouts. Effort classes are relative: **S** = a bounded seam measured in days; **M** = coordinated multi-component work; **L** = an architectural, multi-platform, or multi-release program. They are not delivery commitments.

## 0. Decision summary and corrections to the brief

### Proposed, not decided

Propose **Option C with the B+ policy contract**, in phases:

1. Ship the narrow iteration-1 iOS NTP/modal permit seam without extracting `PromoService`.
2. If the cross-team decision approves C, build/evolve the client arbiter and make it the only authority for **visibility now**.
3. Add bounded remote queue policy for kill, priority, cooldown, caps, and expiry.
4. Feed RMF candidates through a native-surface bridge; migrate the seven Program A header/card/chrome candidates first.
5. Only then decide whether RMF needs per-surface scheduling or generic modal rendering. Those are independently valuable extensions, not prerequisites for a single promo contract.

This is the highest-scoring framing (**95/100**) because it preserves the shipped desktop rule engine, works offline for local promos, adds remote content where it has value, and gives product a remotely controllable policy plane. B+ alone scores **91**, B **79**, and A **56** under the declared rubric in §D. The difference between C and B+ is remote content/targeting: they are complementary, not rival end states.

### Headline findings

1. **Pure Option A is a replacement queue program, not an RMF configuration project.** RMF currently selects one config-order winner, stores one globally scheduled message, and lacks severity, context, cross-message pacing, impression caps, absolute campaign dates, and essential preemption. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:51-78`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:92-125,443-506`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/CoreData/RemoteMessaging.xcdatamodeld/RemoteMessaging 3.xcdatamodel/contents:3-14`
2. **Pure Option B has an honest but non-trivial gap list.** The macOS queue already has fixed priority, internal/external promos, severity/context conflicts, global cooldowns, history, timeouts, debug controls, and tests; it lacks generic remote per-promo policy, caps/absolute expiry, essential preemption, delay telemetry, dynamic registration, pending/retry scheduling, and bidirectional RMF gating. It also remains macOS app-target code. iOS integration needs new lifecycle/result/visibility adapters: the launch-modal group cannot be represented as one usable `InternalPromo` today, and per-provider registration is broader migration work. `macOS/DuckDuckGo/Promotions/PromoService.swift:225-226,322-330,488-553,621-649`; `macOS/DuckDuckGo/Promotions/PromoTypes/PromoHistoryRecord.swift:21-51`; `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+RemoteMessage.swift:24-46`; `macOS/DuckDuckGo/Promotions/PromoDebugMenu.swift:25-41`; `macOS/UnitTests/Promotions/PromoServiceTests.swift:23-29,69-99`
3. **The contract boundary is campaign availability versus visibility permission.** RMF may say “candidate X is active”; only the queue may say “show X now.” A surface adapter re-checks immediate local eligibility and owns actual presentation. This removes the current `ExternalPromo` asymmetry, where RMF controls its own visibility and the queue only reacts. `macOS/DuckDuckGo/Promotions/PromoTypes/Promo.swift:97-124`; `macOS/DuckDuckGo/Promotions/PromoService.swift:431-457`
4. **“One system” should mean one behavior contract and stable IDs, not one binary implementation.** Apple can share Swift; Windows and Android cannot. Windows already has a parallel queue and Android has no global queue — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:44-50`
5. **Chromium prior art points toward C/B+, not A.** Chromium's Feature Engagement component is a client-side backend: clients report events, request trigger permission, and dismiss UI; local event history enforces windows/rates while configuration may be client, server, or mixed. `Chromium //components/feature_engagement/README.md:20-22,157-170,202-252,281-375,403-445,487-545`; [official Chromium source](https://chromium.googlesource.com/chromium/src/%2B/refs/tags/137.0.7151.13/components/feature_engagement/)

### Corrections carried forward

- The research brief's “no experiment/cohort integration” is too broad. RMF supports `expVariant`; privacy-config cohort flags are excluded from `allFeatureFlagsEnabled`. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:24-34,70-81`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/AppAttributeMatcher.swift:111-130`; `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:165-167`
- Adding an RMF surface does **not inherently require a Core Data migration**: surfaces already persist in an `Int16` bitmask. A model migration is needed only if persisted shape/semantics change. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:193-210`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:443-459`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/CoreData/RemoteMessaging.xcdatamodeld/RemoteMessaging 3.xcdatamodel/contents:3-14`
- There is no shared Apple `PromoQueue` package and iteration 1 no longer plans one. The macOS engine remains in `macOS/DuckDuckGo/Promotions/`; extraction is an Option-B/C bill-of-material item only if iteration 3 selects that direction.
- The iOS and macOS 24-hour values are not equivalent policy: iOS persists the last successful presentation through `PromptCooldownManager`, whereas macOS applies app-initiated cooldown from qualifying dismissal history. Matching duration does not remove integration work.
- A pure-A renderer cannot be uniformly “thin.” StoreKit requests, TipKit, OS/default-browser state, live page callbacks, consent mutations, subscription state, and other Program A class-(c) cases retain native logic. If RMF grants visibility and calls those plugins, this is A with substantial native plugins; it becomes C only if the client queue remains the final visibility arbiter. `promo-queue-docs/iteration_2_findings.md:114-157`

---

## A. RQ0 — numbered requirements

The Must/Should/Nice labels below are proposed for the TD. Stakeholder and guidance sources are **reported (Asana), not code-verifiable**. Current implementation citations prove only whether a capability exists today.

### Must

**M1 — Collision safety.** At most one Medium–High interruption is visible; one NTP message is visible; contexts/surfaces declare coexistence; RMF, Next Steps, and native prompts participate in the same decision. Source: Stephen V1 and Mobile Global Guidelines — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:43-53`. Current macOS severity/context checks: `macOS/DuckDuckGo/Promotions/PromoService.swift:517-535`.

**M2 — Frequency and dismissal semantics.** Enforce 1/day app-initiated, 1/hour user-initiated, normally at least 28 days before re-show, and never re-show after explicit rejection. Source: Stephen/mobile/company guidance — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:45-55`. Current initiated cooldowns and permanent result semantics: `macOS/DuckDuckGo/Promotions/PromoTypes/PromoInitiated.swift:21-34`; `macOS/DuckDuckGo/Promotions/PromoService.swift:539-553,653-676`.

**M3 — Deterministic arbitration that delays rather than suppresses.** Every promo has priority, a stable same-priority tie-break, and an eligible loser is recorded as pending and re-evaluated when the blocker clears or at the next relevant trigger. Source: Stephen — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:45-55`. Current macOS priority is fixed array order, but blocked promos are merely skipped during a trigger and cleanup does not retry them: `macOS/DuckDuckGo/Promotions/PromoService.swift:322-330,488-510,621-649`; the test explicitly expects the second medium promo to be skipped: `macOS/UnitTests/Promotions/PromoServiceTests.swift:69-99`.

**M4 — Campaign lifecycle.** Support per-promo impression caps, cooldown, absolute start/end or hard expiry, and persistent badges' time/impression/interaction lifetime. Source: mobile/company guidance and the temporary-campaign ask — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:51-55,73-83`. RMF only has relative `dismissAfterDaysShown`: `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:255-264`.

**M5 — Local eligibility and safety gates.** Suppress app-initiated prompts on onboarding day and external/deep-link launches; allow essential/security content to preempt; re-check live native eligibility immediately before render. Source: Stephen/mobile rules — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:45-53`. Current macOS external-activation and onboarding gates: `macOS/DuckDuckGo/Promotions/PromoService.swift:215-221,237-241,517-553`.

**M6 — Complete coverage of collision-capable promo UI.** Every promo is registered with the common contract even when its content/trigger stays native; utilities and transactional UI may be “not a promo” but still publish visibility if they can collide. Source: single-system/paved-road goal — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:13-22`. Program A reconciled all 74 product names and shadow units: `promo-queue-docs/iteration_2_findings.md:212-249`.

**M7 — Remote removal and bounded control.** Product can disable a promo remotely; priority/cooldown/cap/expiry changes are remotely configurable within compiled safety bounds. Source: Chris's disable/remove axis — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:15-20`. Existing global queue hook and remote cooldown pattern: `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift:912-916`; `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromptCooldownIntervalProvider.swift:29-62`.

**M8 — Privacy-preserving execution.** Configuration is static and identical for everyone; targeting, arbitration, and history stay on-device; no per-user server scheduling/state is introduced. Source: established RMF posture and project constraint. Current CDN/client behavior: `iOS/DuckDuckGo/RemoteMessagingClient.swift:39-44`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingProcessing.swift:81-101`.

**M9 — Deterministic offline and first-fetch behavior.** Local promos and safety rules work before network fetch; cached remote content has an explicit stale policy; a remote kill is never described as instantaneous. Current missing cached config returns `noData`: `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigFetcher.swift:41-62`.

**M10 — Standard measurement and owner accounting.** Emit one canonical shown, unique-shown, dismissed, actioned, delayed/eligible-not-shown, and reason stream; promo owners can observe delivery loss. Standard CTR and delay visibility are **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:17,20`. RMF currently emits shown/dismiss/action pixels but not queue delay: `iOS/DuckDuckGo/HomePageConfiguration.swift:99-123`; `iOS/DuckDuckGo/NewTabPageMessagesModel.swift:121-155`; `iOS/DuckDuckGo/Pixels/RemoteMessagingPixelReporter.swift:31-43,66-127`.

**M11 — Cross-platform consistency without a desktop rewrite.** One normative contract, canonical IDs, and conformance tests must allow Apple sharing and Windows/Android twins; adoption cannot require replacing a shipped desktop queue before parity. Mark's constraint and platform status are **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:15,44-50`.

**M12 — Native authority for safety-critical effects.** Remote configuration may request an action, but consent mutations, OS UI, StoreKit, transactions, and immediate page/runtime decisions remain native and cannot be made less restrictive remotely. Program A examples: `iOS/DuckDuckGo/ModalPromptCoordination/Providers/CookiePopupProtectionOptInModalPromptProvider.swift:88-185`; `iOS/DuckDuckGo/AppRatingPrompt.swift:38-81`; `iOS/DuckDuckGo/TabViewController.swift:4432-4511`.

### Should

**S1 — Remote campaign value where justified.** Support remote copy, localization, imagery, coarse targeting, kill, and campaign sequencing without forcing every native interaction into a generic renderer. Current iOS RMF provides NTP banners, What's New `cards_list`, remote images, and client-side matching. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:23-32`; `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:56-75`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingImageProvider.swift:27-61`.

**S2 — Event-driven response.** Named local events can trigger re-evaluation or self-retirement immediately where product intent requires it; accepting ≤24h latency is an explicit per-promo product decision. The latency trade-off is **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:34,85-91`. Current processor re-evaluates on new version, invalidation, or >24h age: `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigProcessor.swift:49-85`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessagingConfig.swift:24-45`.

**S3 — Operational tooling and diagnostics.** Validate schemas/IDs/policy bounds, preview surfaces, explain eligibility/delay, simulate dates/events, reset/force in debug, and preserve last-known-good config. Current queue debug/history foundations: `macOS/DuckDuckGo/Promotions/PromoDebugMenu.swift:88-228`; `macOS/DuckDuckGo/Promotions/PromoTypes/PromoHistoryRecord.swift:21-51`.

**S4 — Paved-road enforcement and ownership.** Define an AOR, intake/review rules, matcher/action/surface proposal process, ship-review question, documentation, and optional CI warnings. This requirement is **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:31-35,71-83`.

**S5 — Experiments without private server state.** Stable local variants/percentiles may select campaigns, but authoring rules must be explicit and privacy-preserving. RMF already supports `expVariant` and stable per-message percentile. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Matchers/AppAttributeMatcher.swift:111-130`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:139-151`.

**S6 — Reversible, staged migration.** Each increment can ship behind a remote/global flag, preserves existing per-feature state, and avoids an all-platform flag day. PR 1 added disabled-by-default `FeatureFlag.promoPresentationCoordination`, backed by the iOS-specific `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination` in the `FeatureFlags-iOS` package; privacy-config enablement remains a separate staged rollout. `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/iOSPromoQueueSubfeature.swift`.

### Nice

**N1 — Rich low-interruption policy.** Non-essential timeouts, dot/text badge lifecycle, inline-tip coexistence, and surface-specific display behavior are declarative. Source: Stephen/company guidance — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:45-53`. macOS already models type-specific timeouts: `macOS/DuckDuckGo/Promotions/PromoTypes/PromoType.swift:21-158`.

**N2 — Shared implementation where languages permit.** Apple may share policy code if iteration 3 selects a client/hybrid queue; iteration 1 deliberately does not force that extraction. Across Swift/Kotlin/C#, a versioned spec and conformance suite are acceptable. Platform constraints are **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:44-50`.

---

## B. RQ1 and RQ2 — bills of materials

### B.1 Option A — RMF becomes the queue

| Bill of material | Size | Why it is required / release coupling |
|---|---:|---|
| Multi-message/per-surface scheduler and starvation rules | **L** | Processor/store/consumer rework: current matcher selects one winner and store marks other scheduled rows done. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:51-78`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:92-125,443-506` |
| Queue policy model: priority, tie-break, initiated kind, severity, context, coexistence, essential preemption | **L program; M/client** | No equivalent fields exist; current macOS shape demonstrates them. `macOS/DuckDuckGo/Promotions/PromoTypes/Promo.swift:22-58`; `macOS/DuckDuckGo/Promotions/PromoService.swift:517-553` |
| Cross-message history/frequency engine: 1d/1h, cooldown, permanent reject, caps, absolute dates | **L** | RMF state has shown/date/status only; relative shown-days is not campaign expiry. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/CoreData/RemoteMessaging.xcdatamodeld/RemoteMessaging 3.xcdatamodel/contents:3-14`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:255-264` |
| Surface registry and queue-controlled native bridge | **M foundation + S–M/surface** | All 12 Program A blocked candidates need it; seven are header/card/chrome. `promo-queue-docs/iteration_2_findings.md:253-269` |
| Portfolio of first-class/hybrid surfaces | **L portfolio** | Hero/consent sheet, headers, import summary, Duck.ai chrome, floating banner, menu dot, Settings badge, then any literal “all promo” long tail. Generic iOS modal support today is only What's New `cards_list`. `iOS/DuckDuckGo/DefaultRemoteMessagingSurfacesProvider.swift:23-32`; `iOS/DuckDuckGo/ModalPromptCoordination/Providers/WhatsNewModalPromptProvider.swift:71-110,171-208` |
| Event trigger bus and self-retirement | **L general; S/hybrid** | Existing reevaluation is config/invalidation/24h-based. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigProcessor.swift:49-85` |
| Matcher/action expansion | **S each; L aggregate** | At least eight new state families for the 12 known candidates; unknown keys fall back/skip and are release-gated. `promo-queue-docs/iteration_2_findings.md:257-265`; `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:415-423` |
| Offline/bootstrap and stale-kill policy | **M** | No first-fetch config means no RMF candidate. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigFetcher.swift:41-62` |
| Config/localization generation, validation, previews, lifecycle tooling | **M** | Live iOS is already 24 objects/10 IDs/27 rules with inline localization. `promo-queue-docs/iteration_2_findings.md:78-100`; `remote-messaging-config/live/ios-config/ios-config.json#/messages,#/rules` |
| Standard measurement, delay reasons, deduplication, owner reporting | **M + analytics** | Existing RMF pixels do not express queue delay. `iOS/DuckDuckGo/Pixels/RemoteMessagingPixelReporter.swift:31-43,66-127` |
| Debug/test parity and cross-version compatibility | **M** | Eligibility explanation, time/event simulation, surface previews, force/reset. Current queue baseline: `macOS/DuckDuckGo/Promotions/PromoDebugMenu.swift:88-228` |
| Schemas, AOR, approval/rollback flow across all platforms | **M** | Config repo has only iOS/macOS schemas. `remote-messaging-config/schemas/ios/schema.json`; `remote-messaging-config/schemas/macos/schema.json` |
| macOS/Windows replacement or compatibility migration | **L/platform** | Retaining their queues as arbiters makes the result C; removing them before parity violates M11. Windows status is **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:44-50` |

**First honest increment:** per-surface/multi-candidate RMF scheduling plus one queue-controlled native surface bridge. It produces infrastructure evidence; it is not yet an all-promo queue.

### B.2 Option B — client queue is the system; RMF is an input

| Bill of material | Size | Why it is required / release coupling |
|---|---:|---|
| Extract and adapt the current macOS engine into a shared Apple package | **M–L** | Current factory/engine are app-target code, triggers/factory/lifecycle are macOS-specific, and iOS needs new adapters. A whole-modal-group wrapper cannot currently provide non-consuming eligibility, async results, active visibility, or generic `hide()`; per-provider registration is broader work. `macOS/DuckDuckGo/Promotions/PromoServiceFactory.swift:47-78`; `macOS/DuckDuckGo/Promotions/PromoDelegate.swift:33-55`; `iOS/DuckDuckGo/ModalPromptCoordination/ModalPromptProvider.swift:40-50` |
| Add pending-state/re-evaluation scheduling, impression counts/caps, absolute expiry, essential preemption, tie-break rule, and delay reason | **M** | Today evaluation is trigger-driven, a blocked promo is skipped, and cleanup does not retry it; history has dismiss count/last shown but none of the new fields. `macOS/DuckDuckGo/Promotions/PromoService.swift:322-330,488-510,621-649`; `macOS/DuckDuckGo/Promotions/PromoTypes/PromoHistoryRecord.swift:21-51`; `macOS/UnitTests/Promotions/PromoServiceTests.swift:69-99` |
| iOS registration/contexts and adapters for all collision-capable families | **M + S/family** | Program A provides the waves and class-(c) dispositions. `promo-queue-docs/iteration_2_findings.md:283-307` |
| Bidirectional RMF surface bridge with one pixel owner | **M + S/surface** | Current macOS seam observes separate NTP/tab-bar ExternalPromos; it does not make RMF wait. `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+RemoteMessage.swift:24-46`; `macOS/DuckDuckGo/RemoteMessaging/RemoteMessagePromoDelegate.swift:23-80` |
| Basic remote flags/settings | **S/promo; poor at inventory scale** | Global queue flag and modal cooldown prove the mechanism; there is no generic per-promo policy. `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift:912-916`; `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromptCooldownIntervalProvider.swift:29-62` |
| B+ dedicated, validated static policy manifest | **M** | Scales stable IDs, kill, bounded order/cooldown/cap/expiry with last-known-good and compiled defaults. New dimensions remain release-gated. |
| Keep remote-content subset in RMF | **M bridge + S/candidate** | Existing channels plus 12 Program A candidates; transactional/native state machines remain local. `promo-queue-docs/iteration_2_findings.md:114-157,253-269` |
| Android queue-equivalent implementation | **L** | Android has no global queue — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:48-50` |
| Windows/macOS common spec and conformance tests | **M alignment** | Preserve existing engines; Apple alone shares Swift. Windows status is **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:44-50` |
| Queue measurement/owner accounting | **M + analytics** | Add shown/dismiss/action/delayed/eligible-not-shown and reasons, once. |
| Paved-road/AOR enforcement | **M process** | Checklist, docs, ship-review question, review ownership, optional CI warnings — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:35,71-83` |
| Optional RMF per-surface scheduler | **L, deferable** | Needed only when multiple remote-content surfaces must independently remain active; current RMF winner is global. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:92-125,443-506` |

**First honest increment if Option B is selected:** establish the shared engine and a real iOS adapter contract, then add pending/retry, caps/expiry, and delay reason before replacing the passwords screen's private header priority chain with four registered promos. The current private chain is at `iOS/DuckDuckGo/AutofillLoginListViewController.swift:746-795`.

### B.3 What the desktop solution does not support today

The current macOS queue **does** support fixed array priority, internal/observed-external promos, severity/context conflicts, initiated-kind global cooldowns, next-eligible/permanent history, type-specific timeouts, debug controls, and tests. `macOS/DuckDuckGo/Promotions/PromoService.swift:488-553,653-676`; `macOS/DuckDuckGo/Promotions/PromoTypes/Promo.swift:22-58,97-124`; `macOS/DuckDuckGo/Promotions/PromoTypes/PromoType.swift:21-158`; `macOS/DuckDuckGo/Promotions/PromoDebugMenu.swift:25-41`; `macOS/UnitTests/Promotions/PromoServiceTests.swift:23-29,69-99`

It does **not** support:

1. Remote content, translation, imagery, or targeting by itself; those come from separately registered RMF ExternalPromos. `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+RemoteMessage.swift:24-46`; `macOS/DuckDuckGo/RemoteMessaging/RemoteMessagePromoDelegate.swift:23-80`
2. Generic remote per-promo kill, order, cooldown, cap, or expiry policy; promo metadata is compiled and the factory list is fixed. `macOS/DuckDuckGo/Promotions/PromoTypes/Promo.swift:22-58`; `macOS/DuckDuckGo/Promotions/PromoServiceFactory.swift:60-78`
3. Impression counts/caps or absolute campaign start/end; history stores dismiss count, last shown/dismissed, actioned, and next eligible. `macOS/DuckDuckGo/Promotions/PromoTypes/PromoHistoryRecord.swift:21-51`
4. Owner-visible delay/eligible-not-shown reasons or a queue-level measurement standard; blocked items are skipped without a persisted reason. `macOS/DuckDuckGo/Promotions/PromoService.swift:488-510,621-649`; `macOS/DuckDuckGo/Promotions/PromoTypes/PromoHistoryRecord.swift:21-51`
5. Explicit essential-message preemption or an explicit same-priority field; array order is the tie-break and the promo descriptor has no essential field. `macOS/DuckDuckGo/Promotions/PromoService.swift:223-226,488-553`; `macOS/DuckDuckGo/Promotions/PromoTypes/Promo.swift:22-58`
6. Dynamic/config-defined registrations; the promo list is fixed at construction. `macOS/DuckDuckGo/Promotions/PromoService.swift:223-226,287-315`; `macOS/DuckDuckGo/Promotions/PromoServiceFactory.swift:60-78`
7. Pending/retry scheduling when a blocking promo disappears; evaluation is trigger-driven, blocked promos are skipped, and session cleanup does not re-run them. `macOS/DuckDuckGo/Promotions/PromoService.swift:322-330,488-510,621-649`; `macOS/UnitTests/Promotions/PromoServiceTests.swift:69-99`
8. Generic automatic surface coverage; each feature/surface needs a compiled delegate and registration. `macOS/DuckDuckGo/Promotions/PromoService.swift:101-120,223-226,287-315`; `macOS/DuckDuckGo/Promotions/PromoServiceFactory.swift:60-78`
9. Bidirectional control of RMF; current ExternalPromos observe RMF and retract conflicting internals, but RMF does not request a permit. `macOS/DuckDuckGo/Promotions/PromoService.swift:431-457`
10. Multiple concurrent RMF inputs because RMF is globally single-scheduled. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:92-125,443-506`
11. A single cross-platform binary. macOS is app-target Swift; the Windows parallel implementation and Android absence are **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:44-50`
12. iOS/Android long-tail coverage; iteration 1 supplies only a targeted iOS NTP/modal permit seam, not a shared Apple queue. Android coverage is **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:7,44-50`
13. Remote images in the macOS NTP RMF renderer: the shared model accepts a URL, but the renderer maps only local placeholders. `macOS/LocalPackages/NewTabPage/Sources/NewTabPage/RMF/NewTabPageDataModel+RMF.swift:57-71`
14. First-fetch remote-content fallback; local queue promos can work offline, while RMF has no candidate without fetched/cached config. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigFetcher.swift:41-62`

---

## C. RQ3 — Option C contract

### C.1 Layering rules

This is a proposed long-term contract, not the iteration-1 implementation. The narrow iOS permit coordinator has no generic promo registry, history, severity/context policy, or pending scheduler. If C is selected, the follow-up TD must choose whether to evolve that seam or extract/adapt `PromoService`; neither is assumed here.

1. **RMF owns campaign availability:** remote content, localization, imagery, coarse targeting, campaign kill/removal, and RMF message identity. Its output is a candidate, not permission to render. Current RMF target evaluation is local and config-order based. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingConfigMatcher.swift:51-100`
2. **The queue exclusively owns visibility now:** priority, initiated kind, severity, context/coexistence, onboarding/deep-link gates, global and per-promo cooldown, caps, expiry, essential preemption, and delay reason. Current desktop policy demonstrates the core seam. `macOS/DuckDuckGo/Promotions/PromoService.swift:488-553`
3. **The native surface adapter owns immediate truth and rendering:** it exposes local eligibility, idempotent `show/hide`, and actual shown/dismiss/action events. Remote policy may narrow but never broaden compiled safety/consent eligibility.
4. **One actual-presentation event owns accounting:** the integration coordinator records the queue result, updates RMF history, and emits canonical pixels exactly once. Current NTP accounting occurs on appearance, while What's New marks state during presentation, demonstrating why ownership must be explicit. `iOS/DuckDuckGo/HomePageConfiguration.swift:99-123`; `iOS/DuckDuckGo/WhatsNew/WhatsNewRepository.swift:67-75`
5. **Offline is explicit:** local promos and compiled safety defaults work; cached remote candidates may use last-known-good policy; without a config there is no new remote campaign; kills propagate only after delivery.

### C.2 Identity and seam

Use **one bridge object per native surface** and **one queue identity per canonical promo/campaign**:

- `surfaceID`: renderer family, for example `passwords-header`, `bookmarks-header`, `duckai-chrome`, `menu-dot`.
- `promoKey`: stable, cross-platform feature/campaign identity used by queue policy and history.
- `messageID`: RMF campaign/config identity used for RMF dismissal and message pixels.
- Candidate envelope: `{ promoKey, messageID, surfaceID, configVersion, content, targetingResult }`.
- Unknown `promoKey` or unsupported `surfaceID` fails closed as `unsupported`; it is never rendered by fallback guesswork.

The current macOS seam registers one observation-only `ExternalPromo` per RMF surface. External promos control their own visibility, ignore queue cooldown, and are documented for sparing use. `macOS/DuckDuckGo/Promotions/Promos/PromoServiceFactory+RemoteMessage.swift:24-46`; `macOS/DuckDuckGo/Promotions/PromoTypes/Promo.swift:97-124`. That is a useful transition for existing NTP/tab-bar renderers, but not the final queue-owned-visibility contract.

The queue currently has a fixed construction-time list. First-wave candidates can be statically registered; long term, candidate attach/detach needs a validated registry without allowing remote config to weaken compiled descriptors. `macOS/DuckDuckGo/Promotions/PromoService.swift:223-226,287-315`

### C.3 Interface obligations

**RMF → queue**

- Publish candidate added/changed/removed per surface; preserve a delayed candidate without marking it dismissed.
- Supply stable `promoKey`, `messageID`, `surfaceID`, and config version.
- At minimum, produce independent per-surface candidates before multiple RMF surfaces are relied upon; the current global winner is a bottleneck. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/RemoteMessagingStore.swift:92-125,443-506`
- Do not author severity/context/cooldown outside the separately validated B+ policy schema.
- Treat new attributes/actions/surfaces as release-gated proposals. Unknown attributes currently use fallback/skip. `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Mappers/JsonToRemoteMessageModelMapper.swift:415-423`

**Queue → RMF**

- Return one of `admitted`, `delayed(reason,nextEvaluation)`, `temporarilyIneligible`, or `unsupported`.
- Persist delayed native and RMF candidates as pending; re-evaluate them when the blocking visibility/cooldown changes and on the next relevant trigger. This is new queue work: the current macOS engine skips blocked promos and cleanup does not retry them. `macOS/DuckDuckGo/Promotions/PromoService.swift:322-330,488-510,621-649`
- Emit actual shown, dismissed outcome, and action exactly once.
- Support permit revocation/retraction for essential or higher-priority content.
- Prevent a locally ineligible candidate from starving other RMF candidates.
- Export eligible-but-not-shown and delay reason for owners.

**Surface adapter**

- Never render without a current queue permit; re-check local eligibility immediately before render.
- Make `show/hide` idempotent and race-safe; confirm visibility before `actualShown`.
- Keep consent, OS, StoreKit, page/runtime, and transaction effects local.

### C.4 B+ bounded remote-policy manifest

Compiled descriptors remain authoritative for surface, maximum severity/interruption, essential status, safety gates, and “never after explicit rejection.” Remote policy may safely **disable**, **lower priority**, **lengthen cooldown**, **lower a cap**, or **shorten expiry**. Weakening a compiled bound requires an app release and design review.

A production manifest should be versioned and validated with: `promoKey`, `enabled`, bounded `priority`, `cooldown`, `impressionCap`, `startsAt`, `expiresAt`, `minimumClientVersion`, and optional context-specific narrowing. Unknown IDs are ignored and reported; invalid manifests retain last-known-good; absence falls back to compiled defaults. A per-promo Privacy Config pilot is **S**; the scalable dedicated manifest is **M**. Existing hooks: `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift:912-916`; `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/PromptCooldownIntervalProvider.swift:29-62`.

### C.5 Decision tree for every new promo

Aitor's escalation ladder and Marcos's paved-road ask are **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:31-35`

1. **Is it a promo?** Transactional alerts, utilities, and persistent information architecture use their native contract; if their UI can collide, they still register visibility.
2. **Does off-the-shelf RMF meet content, surface, action, matching, and latency needs?** Use an RMF candidate plus queue admission.
3. **Is only a small, privacy-clean matcher/action missing?** Use the RMF proposal process, ship the client vocabulary, then configure it.
4. **Can product simplify the special trigger/targeting requirement?** Record the requirement deliberately dropped.
5. **Must rendering or immediate eligibility remain native?** Use a native-surface/RMF hybrid.
6. **Is remote content not valuable?** Use a queue-registered `InternalPromo` plus bounded B+ kill/policy.
7. **Is it persistent Settings IA?** Keep it local unless a time-bounded campaign need is explicit.
8. **Bespoke and unqueued is not an allowed endpoint.** Escalate an exception through the AOR.

### C.6 Program A migration fit

- **Strong first wave (7):** Sync bookmarks, Sync passwords, Sync data import, Sync Duck.ai, password-import header, Autofill-extension header, Autofill survey.
- **Attention surfaces (2):** Home-row reminder and VPN menu dot.
- **Modal prototypes (2):** Subscription reinstaller and Cookie Pop-up Protection opt-in; consent/subscription effects remain local.
- **Conditional (1):** PIR `NEW` badge only if remote campaign control is worth its complexity; otherwise B+ policy is enough.

These are the 12 Program A class-(b) candidates. Class-(c) page/StoreKit/system-state cases stay local and queue-registered; do not manufacture RMF wrappers solely to claim migration. `promo-queue-docs/iteration_2_findings.md:114-157,253-307`

### C.7 Failure modes and required defenses

| Failure | Defense / invariant |
|---|---|
| One RMF winner starves other surfaces | Per-surface candidate production before depending on independent RMF surfaces; expose starvation diagnostics. |
| RMF config order disagrees with queue priority | RMF order selects remote candidate availability only; queue policy is the sole final priority. |
| Local ineligibility blocks the candidate pool | `temporarilyIneligible` advances/re-evaluates other candidates without dismissing the campaign. |
| A blocked native promo is silently forgotten | Persist pending state/reason and schedule evaluation on blocker clearance plus the next relevant trigger. |
| Double shown/dismiss/action accounting | One adapter event, one integration coordinator, idempotency key `{promoKey,messageID,presentationID}`. |
| RMF message-ID churn resets cooldown history | Stable `promoKey` owns queue history; `messageID` remains campaign telemetry identity. |
| Old client sees unknown key/attribute/surface | Fail closed, report unsupported, obey minimum client version and compiled fallback. |
| Remote kill is late/offline | Say “remote disable after config delivery”; use expiry/defaults and never promise instantaneous kill. |
| Hide/revoke races with render | Permit token/version, idempotent hide, visibility confirmation before shown pixel. |
| Remote policy weakens safety | Only narrowing changes allowed; schema validation plus compiled bounds. |
| Essential content is delayed | Essential flag is compiled/reviewed and bypasses promo cooldown while retracting safely. |
| Platform inventories drift | Canonical ID registry, contract fixtures, platform conformance reports, named AOR. |

---

## D. RQ4 — evaluation

### D.1 Scoring method

Each requirement is weighted **Must 3 / Should 2 / Nice 1**. A cell scores **✓ = 2** (natural fit or bounded extension), **~ = 1** (possible but architecturally awkward/substantial), **✗ = 0** (structural conflict or unacceptable migration). With 12 Must, 6 Should, and 2 Nice requirements, the maximum is exactly **100**. Scores assess the proposed end-state architecture plus the bill of materials—not current feature completeness. A one-mark change on every Must can move a score by up to 36; therefore totals rank the current evidence, not mathematical truth.

### D.2 Options × requirements

| Req. | A: RMF queue | B: client queue | C: layered | B+: remote-policy queue |
|---|---|---|---|---|
| M1 collision safety | ~ rebuild queue semantics | ✓ native queue responsibility | ✓ one arbiter | ✓ one arbiter |
| M2 frequency/dismissal | ~ new RMF history engine | ~ caps/cooldown completion | ✓ queue + remote bounds | ✓ queue + remote bounds |
| M3 delay/determinism | ~ replace first-winner semantics | ✓ after priced pending/retry extension | ✓ contract preserves/retries candidates | ✓ manifest + pending queue |
| M4 lifecycle/caps/expiry | ~ new schema/store | ~ local policy completion | ✓ bounded manifest + queue | ✓ bounded manifest + queue |
| M5 local safety/essential | ~ many native plugins | ~ add essential rule | ✓ native adapter owns truth | ✓ native queue owns truth |
| M6 complete coverage | ~ large surface portfolio | ✓ registration model | ✓ native + RMF paths | ✓ registration model |
| M7 remote kill/control | ✓ core strength | ~ flag proliferation | ✓ RMF + bounded policy | ✓ core strength |
| M8 privacy/on-device | ✓ preserve current posture | ✓ local by design | ✓ both local/static | ✓ static manifest/local |
| M9 offline/bootstrap | ~ bundle/fallback required | ✓ local promos work | ✓ local fallback explicit | ✓ compiled defaults |
| M10 measurement/accounting | ~ new delay layer | ~ new telemetry | ~ shared analytics project | ~ shared analytics project |
| M11 no desktop rewrite | ✗ replacement or C in disguise | ✓ preserve engines | ✓ preserve engines | ✓ preserve engines |
| M12 native safety authority | ~ conflicts with “thin” ideal | ✓ natural fit | ✓ explicit adapter invariant | ✓ compiled bounds |
| S1 remote content/targeting | ✓ core strength | ~ RMF remains separate input | ✓ core strength | ~ optional RMF input |
| S2 event-driven response | ~ new RMF event bus | ✓ local triggers | ✓ local adapter/events | ✓ local triggers |
| S3 operations/debug | ~ rebuild at RMF scale | ✓ existing queue base | ✓ combined tooling needed | ✓ validated manifest + queue |
| S4 paved road/AOR | ~ process needed | ~ process needed | ~ process needed | ~ process needed |
| S5 local experiments | ✓ existing variant/percentile | ~ add queue contract | ✓ RMF where useful | ~ add policy/queue contract |
| S6 reversible staging | ✗ replacement sequencing risk | ✓ incremental registration | ✓ incremental by surface | ✓ incremental manifest |
| N1 rich low-interruption policy | ~ new RMF surface/policy | ✓ type model foundation | ✓ native type + remote content | ✓ native type + policy |
| N2 shared implementation where possible | ✓ shared Apple code + contract elsewhere | ✓ shared Apple queue + contract elsewhere | ✓ shared Apple queue + contract elsewhere | ✓ shared Apple queue + contract elsewhere |
| **Weighted score / 100** | **56** | **79** | **95** | **91** |

### D.3 Decision axes not captured by a single total

| Axis | A | B | C | B+ |
|---|---|---|---|---|
| Effort to credible parity | **L per platform + L core** | **M–L Apple, L Android** | **M–L Apple bridge/arbiter/policy, L Android; optional L RMF scheduler** | **M policy plus chosen client arbiter, L Android** |
| Migration risk | Highest: engine replacement and surface portfolio | Moderate: many registrations, known engine | Moderate: seam/accounting complexity | Lowest-to-moderate: policy validation and registrations |
| Release coupling | High for every new matcher/action/surface | Local features ship normally | Remote vocabulary release-gated; native path remains | New policy dimensions release-gated; values remote |
| Offline | Needs bootstrap design | Strong for local promos | Strong local; explicit RMF stale behavior | Strong compiled defaults |
| Desktop impact | Replace or duplicate shipped work | Preserve | Preserve and improve RMF adapters | Preserve |
| Reversibility | Low until parity | High | High per surface | High with compiled fallback |
| Org/process | New RMF queue AOR and large config operation | Queue AOR needed | Joint contract with clear layer owners | Queue-policy AOR needed |

### D.4 Complementarity

The evidence does **not** justify “A versus B forever.” A coherent sequence, if the cross-team decision selects client-side arbitration, is **targeted iteration-1 permit seam → client-arbiter foundation → B+ policy → C bridges → optional A-like RMF capabilities**. Per-surface scheduling may become valuable after several remote-content surfaces exist; it does not require moving final visibility arbitration into RMF. Conversely, retaining a client arbiter after adding extensive RMF content is still C, not failed A.

---

## E. Migration narratives

### Option A

Build the multi/per-surface scheduler, queue metadata/history, caps/cooldowns/expiry, event bus, surface registry, measurement, tooling, and offline behavior first. Reconcile all **74 reported product names**: retire stale/non-promo aliases, migrate the 12 Program A candidates, wrap active native class-(c) state machines as RMF plugins, replace or temporarily wrap macOS/Windows queues, and build Android parity. The six iOS launch modals cannot be considered migrated until generic modal/consent/native action contracts exist. **First increment:** per-surface scheduler plus one native bridge. **Risk:** keeping desktop queue arbitration during migration is already C. The 74 names are **reported (Asana), not code-verifiable** as product intent; Program A's code reconciliation is `promo-queue-docs/iteration_2_findings.md:212-249`.

### Option B

After the targeted iteration-1 seam, extract/adapt the macOS engine, build real iOS delegate/lifecycle contracts, add pending/retry plus missing cap/expiry/essential/delay policy, replace private priority chains with registrations, and cover every collision-capable Program A unit. RMF remains a registered content source; Windows/macOS retain engines; Android builds the contract in Kotlin. The six launch modals remain native providers but gain queue-controlled admission only after their eligibility/result/visibility seams exist. **First increment:** shared-engine/iOS-adapter proof, then queue policy completion and passwords-header registrations. **Risk:** extraction and provider integration are material, and per-promo flags/hardcoded order do not scale without B+.

### Option C

Build the client-arbiter foundation only after C is approved, including pending/retry scheduling; define stable IDs/accounting; build the native-surface bridge; then migrate the seven header/card/chrome candidates, two attention surfaces, and two modal prototypes. Add B+ bounded policy in parallel. Desktop retains its queue and replaces observation-only RMF seams with permit-based bridges; Android wraps its reported Fire Mode hybrid precedent with the same arbitration contract. **First increment:** static canonical registrations plus a passwords-header bridge. **Risk:** the seam fails if RMF “shown” and client “shown” are not made one event.

### Option B+

Pilot bounded disable/cap/cooldown on three local promos using Privacy Config, then move to a dedicated validated manifest with last-known-good and conformance fixtures. It changes policy, not content: Program A remote-value candidates still use RMF as an input when justified. **First increment:** three-promo policy pilot. **Risk:** remote policy that can weaken compiled bounds becomes a safety/regression surface.

---

## F. RQ5 — proposed recommendation memo skeleton (“the contract”)

### F.1 Proposed end state

**Proposal:** one cross-platform promo contract with client-side visibility arbitration, bounded static remote queue policy, and RMF campaign candidates where remote content/targeting/kill add value. The decision group is Mark, Stephen, Cristian, Chris Thelwell, and O-L/O-A engineers — **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_3_research.md:11-22`

**Explicit non-goals:** one cross-language binary; server-side per-user scheduling; migrating utilities/transactional UI merely to increase an RMF percentage; replacing desktop before parity; instantaneous offline remote kill; remotely weakening consent/safety rules.

### F.2 Contract to approve

- Approve the layer ownership and identity model in §C.1–C.3.
- Approve the bounded-policy rule: remote config may narrow compiled behavior, never broaden it.
- Approve the new-promo decision tree in §C.5 and “unqueued bespoke = exception, not endpoint.”
- Approve measurement ownership: actual render is the only shown event; queue is source of delay reason; RMF retains message-level campaign identity.
- Approve a normative behavior spec plus platform conformance fixtures as “one system.”

### F.3 Ownership proposal

- **Promo Queue AOR:** owns behavior contract, canonical `promoKey` registry, policy bounds, conformance fixtures, exception log, and queue pixels.
- **RMF AOR:** owns candidate/config schema, matcher/action/surface proposal process, campaign validation, config delivery, and `messageID` telemetry.
- **Feature owner:** owns immediate local eligibility, renderer/adapter, consent/transaction effects, product content approval, and outcome interpretation.
- **Joint review:** any new surface, matcher/action vocabulary, severity increase, essential classification, or relaxation of compiled bounds.

This is an ownership proposal for humans, not a code fact.

### F.4 Measurement standard

Required events: `eligible`, `admitted`, `delayed(reason)`, `actualShown`, `dismissed(outcome)`, `actioned(action)`, `expired`, `unsupported`, and `policyRejected`. Canonical dimensions: `promoKey`, optional `messageID`, `surfaceID`, platform, initiated kind, severity, config version, and reason. CTR denominator is `actualShown`; “eligible but not shown” is reported separately and must never be counted as an impression.

Privacy/metrics review must decide retention, cardinality, and whether owner dashboards use pixels or aggregate derived data. Current RMF message pixels can seed shown/dismiss/action but not delay. `iOS/DuckDuckGo/Pixels/RemoteMessagingPixelReporter.swift:31-43,66-127`

### F.5 Enforcement mechanics

1. Publish “How to add a promo” with the §C.5 decision tree.
2. Add ship/design-review question: “What is its `promoKey`, queue registration, remote-disable path, cap/expiry, and pixel owner?”
3. CODEOWNERS/review routing for queue registry, RMF matchers/actions/surfaces, and policy schema.
4. Optional CI warning for new promo-like modal/banner/badge code without a registry declaration; warning first, hard failure only after false-positive review.
5. Generate a platform conformance report listing registered IDs, unsupported surface keys, policy fallback, and pixel ownership.

The process asks are **reported (Asana), not code-verifiable**. `promo-queue-docs/iteration_2_research.md:35,71-83`

### F.6 Scoped follow-up projects

| Follow-up | Size | First shippable outcome |
|---|---:|---|
| Cross-team contract TD, AOR, canonical IDs, pixel ownership | **S** | Approved protocol/decision log |
| Apple client-arbiter extraction/adaptation, only if B/C is selected | **M–L** | Shared engine plus a real iOS eligibility/result/visibility adapter contract |
| Queue pending/retry, caps, absolute expiry, essential preemption, delay reasons | **M** | Blocked candidate retries and shared policy fixtures pass |
| iOS native-surface/RMF bridge foundation | **M** | One permit-gated static candidate |
| Passwords-header queue + four hybrid migrations | **M** | Private priority chain replaced |
| Sync bookmarks/data-import/Duck.ai hybrids | **M** | Three additional registered surfaces |
| Home-row, VPN dot, PIR badge adapters | **S each** | Queue visibility + bounded policy |
| Subscription/Cookie modal hybrid prototypes | **M** | Native action + remote candidate proof |
| B+ policy pilot / dedicated manifest | **S / M** | Three-promo pilot / validated scalable config |
| Standard queue pixels + owner delay reporting | **M + analytics** | Canonical event stream and first report |
| Per-surface/multi-candidate RMF scheduling | **L, conditional** | Two remote surfaces active independently |
| Optional generic RMF modal renderer | **M–L, conditional** | One non-What's-New modal template |
| Class-(c) collision adapters | **M portfolio** | Page/StoreKit/native UI publishes visibility |
| RMF schema/CI drift cleanup | **S–M** | Modeled vocabulary equals validated schema |
| Android queue implementation and contract parity | **L** | Kotlin engine passes shared fixtures |
| Paved-road docs, ship-review question, optional CI warning | **S** | Process adopted and measured |

---

## G. Questions for humans

1. Is the proposed Must/Should/Nice ordering in §A accepted, especially **M11 no desktop rewrite** and **M12 native safety authority**?
2. Does “single system” mean one normative contract and ID registry, or is a single implementation an actual requirement despite platform languages?
3. Is ≤24h RMF trigger latency acceptable per promo, by promo class, or never for event-driven campaigns?
4. Which B+ controls may change remotely? This report proposes only narrowing compiled behavior; may product ever raise priority, shorten cooldown, raise a cap, or extend expiry without a release?
5. What is the required remote-disable service level, and how should offline clients be described? Neither RMF nor Privacy Config can deliver an instantaneous kill while offline.
6. Does product require multiple RMF surfaces to be simultaneously active, or is serialized remote content acceptable for the first C waves?
7. Should queue history key to long-lived feature identity (`promoKey`) across campaigns, or should each campaign reset cooldown/caps?
8. Who owns the canonical pixel contract and the owner-facing delayed/eligible-not-shown report? What retention/cardinality constraints apply?
9. Which content genuinely needs remote copy/imagery rather than only remote kill/policy? Program A identified 12 reasonable candidates, not 12 mandatory migrations.
10. Should What's New remain a queue-controlled internal modal fed by RMF, or become a general RMF modal surface?
11. Are persistent Settings sections/promos subject to queue pacing, or only remote policy and collision visibility? “Next Steps” versus persistent IA needs a product taxonomy decision.
12. Which messages qualify as **essential**, who approves that flag, and what may they preempt?
13. Is Android queue parity staffed as part of this program or a separately sequenced L project? Android status here is **reported (Asana), not code-verifiable**.
14. Who is the Promo Queue AOR, who is the RMF AOR, and which team owns cross-platform conformance fixtures?
15. Should experiment eligibility allow RMF `expVariant`/percentile, and what authoring rule replaces the brief's incorrect “cohort-free” shorthand?

---

## H. Coverage of the research questions

- **RQ1:** Option A bill of materials — §B.1.
- **RQ2:** Option B bill of materials and desktop gaps — §B.2–B.3.
- **RQ3:** layered contract, decision tree, obligations, hybrid candidates, failure modes — §C.
- **RQ4:** requirements-weighted A/B/C/B+ evaluation and migration narratives — §D–E.
- **RQ5:** proposed contract memo, ownership, measurement, enforcement, follow-up projects, and human questions — §F–G.
