# Iteration 2 Research Plan — Extend RMF to Today's Promos

**Purpose:** this is a self-contained research brief for an agent (or human) preparing the plan for the Asana task **"Define future approach for managing Promos"** (task `1216396156310211`, currently an empty shell) and its sibling **"Scope follow-up projects"** (`1216396156310212`). It covers the **iteration-2 slice**: *of the promos that exist in the iOS app today, which could already run through RMF, which are blocked on a missing RMF capability (and exactly which capability), and what it would take to close each gap.*

**You (the research agent) have:** the `apple-browsers` monorepo (`/Users/bkunat/Desktop/ddg-workspace/apple-browsers`) and the RMF config repo (`/Users/bkunat/Desktop/ddg-workspace/remote-messaging-config`) locally. **You do NOT have Asana access** — every relevant Asana discussion is digested in §2 below; treat it as ground truth for *positions and decisions*, and the code as ground truth for *technical facts*. Where the two conflict, flag it — that's a finding.

**Sibling doc:** `iteration_3_research.md` covers the longer-horizon question (*can RMF become the promo queue itself?*). Do not answer that here; this doc's output is an input to it.

---

## 1. Where this sits in the project ladder

1. **Iteration 1 (implementation in progress; DRI Bartosz):** "stop the bleed" — extend the existing iOS launch-modal coordination with a small app-level cross-surface permit coordinator so NTP RMF and launch modals cannot overlap. `Foreground`/`UIInteractionManager` retain lifecycle readiness; `PromoCoordinationService` keeps launch-source and unrelated-modal gates; `ModalPromptCoordinationManager` keeps provider-level onboarding eligibility, priority, cooldown, and presentation while holding the mutual-exclusion lease until a checkpoint confirms the presented modal root is gone (providers gain no dismissal signal, but adapters revalidate prepared/retained work); NTP reports actual RMF visibility and waits unconsumed after modal commit. PR 1 merged on 2026-08-04; final PR 2 now contains lifecycle-safe scheduling, the NTP render gate, and all three host paths and is awaiting review. macOS `PromoService` is **not** extracted for iteration 1. Design: `promo-queue-docs/TECH_DESIGN_FINAL.md`.
2. **Iteration 2 (this research):** extend RMF to missing promo surfaces and classify the rest. The leading hypothesis is "migrate what can migrate to RMF and keep native eligibility/rendering where required," but the long-term arbitration mechanism is deliberately **not pre-decided**.
3. **Iteration 3 (sibling doc):** decide the end state — RMF *as* the promo queue (everything remote-configurable) vs. a client-side queue with RMF as one input vs. a combined model.

**Why this matters (the product problem):** ~75% of DDG-originated pop-up complaints are frequency-driven, not intrinsic; "annoying pop-ups" ranks #21 on iOS (9.4%) in the Q2 2026 survey. There is no central mechanism to sequence or suppress competing promos; the In-product promo guidance is aspirational, not enforced. Every objective keeps shipping bespoke promos (most recently Android's Fire Mode cards) because the paved road doesn't exist yet.

---

## 2. Asana context digest (you can't fetch this — it's all here)

### 2.1 The decision history in one paragraph

May 26, 2026: scope debate on the main task ([iOS & Android] Implement Promo Queue, `1214299397742171`) — Ben S argued the queue is needed for **over-saturation control and visibility/instrumentation** ("which promos are shown, where, when"), not because of observed mobile collisions; RMFs were then out of scope because "there's no reliable way to predict when an RMF will appear." Jul 7–8: the initial direction was to reuse the macOS queue for iteration 1, extend it to the rest of the promos, and feed RMF into it. Jul 9: fresh thread on RMF gaps (see §2.3). Jul 10: kick-off. Subsequent code/history review changed the iteration-1 recommendation: preserve the existing iOS modal system and add only bidirectional NTP/modal permits. The Jul 7–8 direction remains relevant historical context for iteration 3, not the implementation baseline.

### 2.2 The "why not RMF?" conversation — claims and corrections

This is the single most important context for iteration-2 research, because it defines the *kind* of answer people expect (verified gaps, not vibes):

- **Aitor (Android, Fire Mode thread, Jun 30):** "Why isn't RMF the default for all promos [on surfaces where RMF already operates]? … The default conversation should be: Why not use RMF? If RMF isn't sufficient, can we extend it? If certain requirements (e.g. trigger rules) are too specific for RMF, can we simplify or descope them? Only if we've exhausted those options should we build a bespoke implementation." Chris Thelwell agreed and floated RMF-as-the-queue (iteration-3 territory).
- **Craig Russell (Jun 30 + Jul 9):** the real, recurring blocker is **surfaces**: "RMF only supports showing a message in certain places in the app. There are other places where we want to show some promo, and RMF doesn't know about every possible surface … Both parts of the puzzle need to be supported: a centralised way of managing a promo queue which can know about promos in surfaces beyond what is supported today, and a way of tying into that remotely (e.g., using RMF)."
- **Pablo (Jul 9, main task):** claimed teams avoid RMF because "we cannot trigger iOS/Android settings from the RMF" (e.g. a Sync promo that opens Settings > Sync & Backup). **Cristian's correction (Jul 9): RMF supports in-app navigations; adding that specific navigation is straightforward — "that should never be a blocker to use RMF, and probably has been more a wrong assumption, or missing conversation."** → **Preliminary code check (Jul 10) confirms Cristian:** the client `NavigationTarget` enum already includes `sync`, `settings`, `settings.general`, `duckai.settings`, `import.passwords`, `appearance`, `pir.main`, `feedback` (`SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/Model/RemoteMessageModel.swift:356-366`; iOS handles all but `softwareUpdate` via `iOS/DuckDuckGo/MessageNavigator.swift:50-73`). Re-verify, then state it plainly in your report — separating "perceived gaps" from "real gaps" is explicitly what the project must do. Cristian's framing of the end goal: "Objective wants to do a promo, can I use RMF? Yes, perfect. No, why not? Can we extend the framework? Can we simplify the requirements? If all of the above is not possible, then exceptions can happen, but last resort."
- **Ondrej (Android, Fire Mode DRI):** "There was an explicit product requirement for it not to be an RMF" (temporary 3-week campaign, event-driven trigger) — yet after the thread, the NTP fire promo **was** converted to RMF by *dropping a requirement* (the "user burned tabs" trigger; Sveta suggested the drop, which also increased reach). Trigger latency was the sticking point: RMF rules re-evaluate on config download / 24h invalidation, so a promo can lag an event by up to a day. **Chris Thelwell explicitly accepted that trade-off** for this case ("they would see it next time they use the Fire Button after 24 hours … I think this is OK").
- **Marcos (recurring):** how do we stop new bespoke promos landing outside the queue/RMF? Kick-off answer: paved-road docs + announcement + a ship-review/design-review question ("does this promo go through the promo queue or RMF, and can it be disabled remotely?") + optionally CODEOWNERS/Danger warnings on new modal/NTP-promo code.

### 2.3 Mark's constraint (from the DRI<>PA task and kick-off thread, Jul 8)

Mark (desktop): Mac **and Windows** already solved conflicts and built a promo queue with rules defined by Stephen; Chromium has a similar feature we can use; he is "not so sure that RMFs is the solution," and before any decision wants: **(a) a set of requirements for what we want from a Promo Queue, (b) a list of what the current Desktop solution doesn't support.** He "would prefer to improve an existing system, rather than start again, which would either introduce another divergence, or force desktop to replace its existing implementation." The long-term task must include Mark, Stephen, and O-L engineers. Chris Thelwell's version: "we have two candidates plus a combined approach as a starting point but we don't have a good way to evaluate the options" → step back, define needs, then run a TD task. **Practical consequence for this research: every gap you report must be phrased against a requirement, and "extend RMF" findings must be symmetric with "what the desktop queue already does."**

### 2.4 The requirements baseline (reproduce-worthy content)

**Stephen's "Rules and Guidelines V1" (Asana `1213119765994047`, the desktop queue's requirements source):**

- Global presentation rules: only one Medium–High interruption message at a time (no overlapping dialogs/panels/bars/modals); only one **app-initiated** Med–High interruption per **day**; only one **user-initiated** per **hour**; don't promote the same feature more than once (or rare long cooldown); **only one NTP message at a time** (no app-initiated prompt while Next Steps is active; no RMF while Next Steps is active); prompts not shown when app launched from deep links / other apps / notifications; [nice-to-have] non-essential prompts time out if not interacted with.
- Message properties model: triggers; conditions (is something else visible; has it been shown before; type; category; **context = Browsing | New Tab**); display behavior (timeout).
- V1 prompt types (desktop): feature-discovery tip, info bar, tab modal, application modal, **RMF**, Next Steps, [nice-to-have] text badges, dot badges, nudge buttons, inline tips.
- Open questions Stephen logged: how to handle two same-priority messages; is there a simpler version; what if an *essential* message (critical security update) needs to preempt a visible one.
- Note in that doc: "iOS rule and tech design — the types of messages and surface areas are much more constrained."

**Mobile "Global Guidelines" (Asana `1214130328245985`, in the Mobile Apps Promos & Messaging project):** persistent promos auto-disappear after days/sessions; generally one promo per session; app-initiated high-interruption limited to 1/day; "NEW" text badges expire on time OR impressions OR interaction; same CTA not re-shown too quickly — **never** after an explicit "No Thanks/Don't/Never", otherwise usually ≥28 days; only one Med–High interruption at a time, no stacking, decided by a **priority system**; one NTP message at a time (no app-initiated prompt while RMF is active); no prompts on launch from deep links/other apps/notifications; app-initiated promos need longer intervals; **no app-initiated Med–High prompt on the day of onboarding**.

**In-product promo guidance (Asana `1210875235779852`, company-wide, published Jan 2026):** CTAs/tips clearly dismissible; auto-expire after days/impressions (higher-visibility surfaces → lower caps); understand same-session CTA collisions before adding a new one; "New" badges ≤30d menus / ≤7d NTP with a hard expiry across users; ≥28d re-show cooldown, longer/never on active dismissal; consider dismiss-on-scroll/whitespace; dot-badges disappear on click. Definitions used org-wide: CTA / cross-sell / upsell / tip / dot-badge / text-badge.

**Two operational requirements from the desktop threads worth carrying into iteration 2:** Stephen — the queue should **delay, not suppress** promos; Abhishek — promo *owners* need visibility when their promo is delayed/not shown (impression accounting), or they'll wonder why impressions dropped.

### 2.5 The product-side promo inventory (Mobile Apps Promos and Messaging project, `1214128462307735`)

This is product's living inventory of mobile promos (name-level; verify each in code — §3 RQ2). Chris Thelwell's kick-off subset for "NTP, floating banner and Main Browser, iOS only" is marked ★; his annotations in parentheses.

- **Modals/sheets/alerts:** Win Back Promotion ★ · Subscription Promotion (Returning Users) ★ · VPN Expired Entitlement Alert ★ · Default Browser Prompt · Set As Default Browser — Active User ★ · Default Browser Reactivation (Inactive Users) ★ · What's New Modal ★ (annotated "Managed by RMFs") · AI Chat Address Bar Choice ★ ("Do we still use this?") · New Address Bar Option Bottom Sheet (Duck AI) · App Enjoyment / Rating Dialog · Enable Credential Provider Extension Sheet · Import Passwords Sheet · Privacy Pro Subscription Promo (Skipped Onboarding) · Win-Back Prompt · Browser Comparison (Reactivation)
- **NTP / cards / banners:** Return to Tab Card ★ ("probably out of scope") · Add to Home Screen ★ · Set As Default Browser Message (NTP Low Priority) · Indonesia Regional Promo Card (NTP) · Sync Chat Promotion · Bookmarks Sync Promo · Sync Passwords Promotion · Sync Bookmarks Promotion · 7-Day Trackers Blocked Info
- **Next Steps / Settings promos:** Next Steps Section Hide (14 Days) · Voice Search (Next Steps) · Address Bar (Next Steps) · Add Widget (Next Steps) · Import Google Passwords (Complete Setup) · Get Desktop Browser (Complete Setup) · Next Steps (Settings) · Complete Setup (Settings) · Subscription Settings Menu Promo · Settings — VPN Status
- **List-surface promos:** Import Passwords Promo (Passwords List) · Sync Promo (Passwords List) · Extension Promo (Passwords List) · Autofill Survey Promo (Passwords List) · Survey In Passwords Promo · Import Passwords In Passwords Promo · Import Passwords from Google
- **Menu / badge / dot surfaces:** VPN Row (Menu) · Fire Tabs Promo (Browsing Menu) · Default Browser Row (Menu Item) · Win-Back Offer Badge · Identity Theft Protection "NEW" Badge · Browsing Menu Dot · Browser Menu Button Blue Dot · Tab Switcher Dot · Tab Switcher Unread Dot · Downloads Dot · Downloads Menu Row Dot · Tabs Toolbar Highlighted Icon · PIR Beta Pill · VPN "Try for Free" Pill · Subscription Upsell Banner (App TP) · Sync Row Warning
- **Duck Player:** Duck Player Introduction · Duck Player Toast · Duck Player Native UI Welcome · Duck Player Feature Explainer (SERP Result or YouTube)
- **Toasts/dialogs with promo plugins:** Bookmark Added (with Sync Promo) · Bookmark Added Confirmation Dialog (with Promo Plugins) · Duck AI Address Bar Option
- **Other:** Email Protection Sign-Up · Widget Instructions Promo · Home Screen Widget Auto-Add · Favorites Add Instructions · Broken Site Prompt · Cookie Consent Notifications · App Tracking Protection Tracker Badges · Privacy Status Indicators · Tab Switcher Tracker Count · Trackers Blocked Animation
- **Recently removed (don't count):** Try Fire Tabs (completed) — the iOS **Fire Tabs NTP promo and Tabs Manager tooltip were removed** in project "[iOS] Remove Fire Tabs promos" (completed Jul 3, 2026).

The project also holds the **taxonomy docs**: "UI Pattern Types & How to Use Them" (modals user/app-triggered, inline/floating/persistent banners, tooltip (proposed), Complete-Setup and Next-Steps settings promos, inline attention badges, dot badges — each with when-to-use rationale) and "👉 How to Add a New Promo" (an Asana intake **form** — the process artifact the kick-off wants pointed at the queue/RMF paved road).

### 2.6 The Android precedent: Fire Mode promo → RMF (TD approved Jul 2)

Android just did, end-to-end, exactly what iteration 2 would do per-promo on iOS ("Tech Design: Fire mode RMF promo (Android)", `1216213068497872`, approved). Treat it as the **unit-of-work reference**:

- Added one action: `fireTabsPromo` → opens the tab switcher in Fire mode (JSON action type + mapper + command).
- Added two boolean matching attributes: `fireModeAvailable` (capability gate, used in `matchingRules`) and `fireModeUsed` (engagement signal, used in `exclusionRules`) — one plugin implementing both, following the per-feature RMF attribute pattern.
- **Self-retire:** an observer watches for first Fire-mode entry, sets `fireModeUsed`, and dismisses the active message immediately (attribute re-evaluation alone would wait for the next config download).
- **Hybrid surface trick:** the tab-switcher banner is rendered **natively, not by RMF**, but is *keyed to RMF state* — it shows only while the FIRE_TABS message is the active RMF message, inheriting its matching/exclusion rules, plus two local conditions and its own pixels. This is a live precedent for "RMF schedules; a native surface renders."
- Campaign window (3 weeks) enforced **server-side** by pulling/disabling the config — no client expiry code.
- Illustration via **remote image URL** — reviewer (Noelia): "we support remote placeholders now" (Android; verify iOS parity).
- Process: new matching attributes must be **proposed and documented** in the Remote Messaging Asana project (`1207619243206445`, "Matching Attribute" section, list `1207619413684520`) so other platforms can adopt them. Example proposal to mimic: `ntpAfterIdleState` (iOS) — a 3-state attribute combining after-idle eligibility with return-to-tab-card visibility, using reciprocal `messageShown` exclusions between two message copies; discussion emphasized "bake all states in now — adding values later is release-gated."

### 2.7 Known-hard constraints (already conceded in threads — don't rediscover, verify and quantify)

1. **Trigger latency:** RMF rules evaluate on config download / 24h invalidation (confirmed by Ondrej; also why iteration 1 *observes* RMF instead of predicting it). Event-driven promos ("promo right after the user does X") need either local logic, an accepted delay (CT accepted it once), or a client-side evaluation trigger extension.
2. **No modal-sheet surface today** (stated as hard fact in the kick-off task): RMF on iOS renders NTP cards; What's New consumes RMF content through the modal prompt path. Verify the exact surface list in code.
3. **New matching attributes/actions are release-gated:** the attribute vocabulary is hardcoded in the client, so config can only use what the installed app version understands.
4. **RMF selection semantics (verified Jul 10, re-verify):** no priority field — **config-file order is the priority**, first message passing matching/exclusion rules wins (`RemoteMessagingConfigMatcher.evaluate`). Worse for iteration-2 purposes: the store keeps **exactly one `scheduled` message at a time across ALL surfaces** (`RemoteMessagingStore.saveProcessedResult` marks every other scheduled message `done`) — an NTP banner and a What's New modal cannot be live simultaneously; "queueing" is emergent (dismiss → invalidate → next refresh promotes the next eligible message). macOS uses `PromoService` for broader cross-promo policy; iOS currently has its seven-provider launch-modal priority/cooldown plus the narrow iteration-1 NTP/modal permit design. RMF itself has **no impression caps or cooldowns** — only `displayConditions.trigger: "after_idle"` (iOS-only in practice) and `dismissAfterDaysShown`.
5. **Remote images DO exist on iOS** (parity with Android confirmed): `imageUrl` supported for medium/big*/promo/cardsList templates with dedicated URLCache + prefetch + load pixels (`RemoteMessagingImageProvider.swift`); the `placeholder` enum (22 client-bundled assets) is the release-bound part.

---

## 3. Research questions (the actual work)

Produce a single markdown report answering RQ1–RQ5 in order; each claim cited to `file:line` or a schema path. Where you contradict an Asana position digested above, call it out explicitly (e.g. "Pablo's settings-navigation gap is real/not real because …").

### RQ1 — RMF capability map, verified in code (the "spec vs. supported" cross-check)

From `/Users/bkunat/Desktop/ddg-workspace/remote-messaging-config` (`schemas/` per platform, `templates/`, `samples/`, `live/`) and the client (`SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/`, iOS integration in `iOS/DuckDuckGo/` — start at `RemoteMessagingClient.swift`, `RemoteMessagingConfigMatcherProvider.swift`, `HomePageConfiguration.swift`, `NewTabPageMessagesModel`, `HomeMessageView`, and the What's New provider under `iOS/DuckDuckGo/ModalPromptCoordination/`):

1. **Templates/content types** supported per platform (e.g. small/medium/bigSingleAction/bigTwoAction/promo…), and which **surface** each renders on for iOS specifically. Enumerate every iOS-render path (NTP card; What's New/modal consumption; anything else). Compare with current macOS NTP + tab-bar support and note Android/Windows schema differences at name level.
2. **Matching attributes**: the full iOS vocabulary (schema `matchingAttributes` + `MatchingAttributes.swift` + user/device/app matchers), flagged shared vs. platform-only; percentile/cohort targeting; `messageShown`-style cross-message exclusion; `allFeatureFlagsEnabled` (privacy-config coupling).
3. **Actions**: full iOS action vocabulary — especially **navigation targets** (this settles the Pablo/Cristian dispute: can an RMF action deep-link to Settings > Sync & Backup today? Which screens are reachable? How hard is adding one?), plus url/appStore/share/dismiss/survey.
4. **Lifecycle**: exactly when rules re-evaluate (fetch cadence, invalidation, foreground events?); how one message is chosen among several eligible (order? priority?); dismissal semantics and storage; shown/dismissed pixels and what measurement exists (the main task lists "standard approach to promo measurement" as a stretch feature — document what's already there, e.g. CTR-computable pixel pairs); whether ANY impression-cap / re-show-cooldown mechanism exists inside RMF (guidance demands 28-day cooldowns and expiry — can RMF express that today? `daysSinceInstalled`? nothing?).
5. **Content/localization pipeline**: how message copy gets translated; remote image/placeholder support on iOS (Android has remote illustrations — parity?).
6. **What's live**: inventory `live/ios-config.json` (and skim macOS/Android/Windows) — every live message id, template, targeting gist. This is the ground-truth list of what RMF already carries in production (recent git log of the config repo shows YouTube ad-blocking promos, PIR freemium, Windows preview promos, etc.).

### RQ2 — iOS promo inventory from code, reconciled with product's list (§2.5)

For each promo found in code (start from the seven `ModalPromptCoordination` providers, the RMF NTP card, then the long tail — sync promos (`SyncPromoManager`), autofill/passwords import prompts, home-row/add-to-home-screen reminder, app rating dialog, Duck Player intro/pills/toast, Email Protection sign-up, widget promos, VPN/subscription/win-back surfaces, menu dots & badges, surveys, favorites nudges, "browsing menu" highlights):

- surface type (use the taxonomy names from §2.5's UI Pattern Types where possible)
- trigger + eligibility conditions (and where they're hardcoded)
- config source today: hardcoded / privacy-config flag / RMF / other remote
- state storage (which store/UserDefaults key)
- dismissal/cooldown/expiry behavior vs. the guidance in §2.4 (flag violations — e.g. no cap, no expiry; these are Beah's "unforced errors" and good migration motivators)
- `file:line` pointers
- reconcile with §2.5: product-list items with no code counterpart (stale) and code promos missing from the product list (shadow promos) are both findings.

### RQ3 — The three-way classification (the core deliverable)

For every RQ2 promo, classify with one-line justification:

- **(a) RMF-ready today**: content + targeting expressible with current iOS templates/attributes/actions on a surface RMF already renders on iOS. (Expect: several NTP-card promos — e.g. sync/bookmarks promos on NTP, regional promo cards; check Chris's ★ subset first: win-back, subscription-returning, VPN-expired-entitlement, set-as-default active + reactivation, add-to-home-screen, AI-chat-address-bar-choice.)
- **(b) Blocked on a named RMF gap** — name the *exact* missing piece per promo, one of: missing **surface** (modal sheet, list-section header, menu row/badge/dot, pill/toast, settings row, tab-switcher…), missing **action** (which navigation target), missing **matching attribute** (which local state — and would it be a reasonable, privacy-clean attribute per the proposal process in §2.6), **trigger latency** (event-driven UX that can't wait ≤24h and can't be simplified the way Fire Mode dropped its burn rule), or **local-runtime dependency** RMF can't see. For each gap, note whether the Android Fire-Mode TD pattern (action + attributes + hybrid native surface keyed to RMF state) would close it, and the rough shape of the extension.
- **(c) Should stay client-side** — tightly coupled to local timing/state or system UI (candidates: app rating dialog (StoreKit), broken-site prompt, credential-provider enable sheet, onboarding-adjacent widget promo, privacy-stats indicators that aren't really promos); say why, and whether it should publish visibility to a future common arbitration contract. Iteration 1 coordinates only NTP RMF and the existing launch-modal group; it is not a generic registration mechanism.

Then order (a)+(b) into a **draft migration sequence** (value × effort): suggested first wave = Chris's ★ NTP/modal set that also collides most; call out promos whose guidance-violations (no caps/expiry) make them urgent.

### RQ4 — Division of labor: what RMF-migration does NOT solve

Make explicit, for the plan's "features include" list (modal sheets as RMFs? rules incl. disabling? standard measurement?):

- what migrating a promo to RMF buys (remote content/targeting/kill, measurement pixels, translation pipeline)
- what still needs the client queue even for migrated promos (cross-promo frequency caps per §2.4 rules, priority vs. non-RMF promos, "delay don't suppress", context/severity conflicts, owner-visible impression accounting)
- what *neither* does today (per-promo impression caps and hard expiry enforcement per the guidance; standard CTR dashboards?) — these become explicit follow-up scope items for `1216396156310212`.
- explain how the iteration-1 permit seam affects migrated promos: NTP RMF participates through the targeted render gate, but every additional RMF/native surface still needs explicit visibility, accounting, and arbitration integration. Do not assume an iOS `ExternalPromo` registration path exists.

### RQ5 — Effort model + risks

- Per-gap effort classes using the Android TD as the calibration point (attribute+action+message ≈ small; new surface ≈ medium/large; client-side trigger extension ≈ large + cross-platform design).
- Release-gating: which migrations need app releases (new attributes/actions/surfaces) vs. config-only.
- Risks: 24h latency regressions for event-driven promos; losing A/B or fine-grained local logic in "simplify the requirement" migrations (document what was dropped, Fire-Mode style); iOS/Android divergence if attributes aren't proposed cross-platform (§2.6 process); measurement discontinuity (existing bespoke pixels vs. RMF pixels).

---

## 4. Starting code map (verified Jul 7–10, 2026 — extend, don't re-derive)

- **RMF config repo layout:** `schemas/` (per-platform JSON schema — iOS schema had `allFeatureFlagsEnabled` at `schemas/ios/schema.json:425`), `live/` (production configs, e.g. `live/ios-config.json`), `samples/`, `templates/`, `README.md`.
- **RMF endpoints:** iOS fetches `remotemessaging/config/v1/ios-config.json` from `staticcdn.duckduckgo.com` — URL set at `iOS/DuckDuckGo/RemoteMessagingClient.swift:43`. Static config + client-side rules engine; `RemoteMessagingConfigMatcher.evaluate()` picks at most one message on-device; re-evaluation on config download / 24h invalidation (`RemoteMessagingConfigProcessor`).
- **Privacy-config relationship:** privacy config gates RMF (`remoteMessaging` feature key → `PrivacyConfigurationRemoteMessagingAvailabilityProvider`, `RemoteMessagingAvailabilityProviding.swift:43`; pipeline short-circuits in `RemoteMessagingProcessing.swift:82`); RMF rules can target privacy-config flag state via `allFeatureFlagsEnabled` (client list built at `iOS/DuckDuckGo/RemoteMessagingConfigMatcherProvider.swift:165` from `FeatureFlag.allCases`). Details: `promo-queue-docs/lesson-rmf-privacy-config-relationship.md`.
- **iOS NTP card render path:** `HomePageConfiguration` → `NewTabPageMessagesModel` → `HomeMessageView`; legacy local home messages are dead code (`HomeMessageStorage.messagesToBeShown` returns `[]`) — the iOS NTP renders RMF cards only.
- **iOS modal queue:** `iOS/DuckDuckGo/ModalPromptCoordination/` — seven providers in priority order: WinBack → Subscription (reinstaller) → Subscription (existing user) → AddressBarPicker → DefaultBrowser → What's New (consumes RMF `.modal`-surface content) → CPM opt-in; global privacy-config cooldown; standard-launch gating in the service and provider-level onboarding gating in the manager.
- **macOS queue (iteration-3 comparison, not iteration-1 source):** `macOS/DuckDuckGo/Promotions/` — `PromoService` (~700 lines), `PromoTypes/`, `PromoHistoryStore`; RMF integrated as two observation-only `ExternalPromo`s (`remote-message-ntp`, `remote-message-tabbar`) over `ActiveRemoteMessageModel`. iOS promo list and lifecycle contracts differ materially; see `promo-queue-docs/TECH_DESIGN_FINAL.md` (the iOS inventory divergence it absorbed: no NTP Next Steps cards on iOS, legacy local home messages are dead code, iOS-only surfaces have no macOS counterpart).
- **Feature flag:** PR 1 added disabled-by-default `FeatureFlag.promoPresentationCoordination`, mapped to the iOS-specific `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination` in the `FeatureFlags-iOS` package. The macOS queue retains its separate `promoQueue` flag/default. Privacy-config enablement for the iOS subfeature remains a separate rollout action.

**Deeper ground truth:** `iteration_2_research_appendix.md` (same folder) holds two machine-generated, `file:line`-cited reports: **Part 1 — RMF capability map** (templates/surfaces matrix, all 44 matching attributes, actions incl. navigation targets, selection/lifecycle semantics incl. the single-scheduled-message constraint, live-config inventory, gap list) and **Part 2 — iOS promo inventory** (every promo with trigger/eligibility/config-source/storage/pointers, the macOS `PromoServiceFactory` table, and a preliminary (a)/(b)/(c) classification with named gaps). **Start from the appendix, verify its claims, and extend it — don't re-derive it.** Your RQ3 output should be the appendix Part 2 §9 classification: confirmed, corrected, and completed against the product list in §2.5. Trust code over the appendix on conflict.

## 5. Deliverable format

One report (markdown) with: §A capability matrix (RMF feature × iOS/macOS/Android/Windows, "supported / partial / missing", each cell cited); §B promo inventory table (promo × surface × trigger × config source × storage × guidance-compliance × classification a/b/c × named gap); §C gap list ranked by how many promos each gap unblocks (expect "modal-sheet surface" and "menu badge/dot surface" to rank high — verify); §D draft migration sequence + effort classes; §E open questions for the humans (product intent questions, e.g. "is 24h latency acceptable for X?" — mark clearly, don't guess).

## 6. Out of scope here

- Choosing between "extend RMF" vs "extend desktop queue" vs combined as the end state — that's `iteration_3_research.md` (your §A/§C outputs feed it).
- Designing the queue↔RMF end-state architecture.
- Android implementation detail beyond the precedents above.
- Any Asana writes; this is research only.

## 7. Asana link ledger (for humans reading your report)

- Main project task: `https://app.asana.com/1/137249556945/task/1214299397742171` · Define future approach: `…/task/1216396156310211` · Scope follow-ups: `…/task/1216396156310212`
- Kick-off (decisions/notes): `…/task/1214300205792376` · DRI<>PA (Mark/Cristian positions): `…/task/1214300205792372`
- Fire Mode thread (Chris↔Aitor↔Craig): `…/task/1216107774194120` · Android Fire-Mode RMF TD: `…/task/1216213068497872` · Android promo-conflict task: `…/task/1216146972756295`
- Requirements: Stephen's Rules V1 `…/task/1213119765994047` · Mobile Global Guidelines `…/task/1214130328245985` · In-product promo guidance `…/task/1210875235779852` · UI Pattern Types `…/task/1214119563436376`
- Inventories: Mobile Apps Promos & Messaging project `https://app.asana.com/1/137249556945/project/1214128462307735/list/1214118253636169` · RMF matcher proposals `https://app.asana.com/1/137249556945/project/1207619243206445/list/1207619413684520` (example: `ntpAfterIdleState` `…/task/1216034379142815`)
- Desktop queues: macOS `…/task/1208645854909942` · Windows `…/task/1212808524770775` · [iOS] Remove Fire Tabs promos `…/task/1215103001185355`
