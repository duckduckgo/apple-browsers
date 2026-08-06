# Iteration 3 Research Plan — Should RMF Become the Promo Queue?

**Purpose:** self-contained research brief for an agent (or human) preparing the *strategic* half of the Asana task **"Define future approach for managing Promos"** (`1216396156310211`): **can RMF become the promo queue long-term — and is that a good idea — or are we better off keeping the promo queue client-side (with RMF as one input), or running a combined model?** The output must be usable as the evaluation groundwork for the cross-team TD that Chris Thelwell wants ("we have two candidates plus a combined approach as a starting point but we don't have a good way to evaluate the options").

**You (the research agent) have:** `apple-browsers` (`/Users/bkunat/Desktop/ddg-workspace/apple-browsers`) and the RMF config repo (`/Users/bkunat/Desktop/ddg-workspace/remote-messaging-config`) locally; **no Asana access** — all discussion context is digested here. **Read `iteration_2_research.md` first** (same folder): it holds the shared Asana digest (§2 there) and its output — the RMF capability map and the promo inventory/classification — is this doc's main input. Do not redo that inventory work.

**Timeline note:** iteration 1 (due Jul 31, 2026) no longer extracts macOS `PromoService`. Its iOS baseline is deliberately narrow: `Foreground`/`UIInteractionManager` retain lifecycle readiness; the existing modal service retains onboarding, launch-source, and unrelated-modal gates; the existing manager retains provider priority/cooldown/presentation and publishes active lifecycle; a small app-level permit coordinator arbitrates that modal group against actually visible NTP RMF. This is useful evidence for permit-based layering, but **candidate B remains a future option**, not shipped/shared iOS infrastructure.

---

## 1. The question, stated the way the stakeholders will judge it

This is **not** "is RMF good?" It is: *which system is the single, org-wide way promos get scheduled, arbitrated, controlled, and measured — and what's the migration path that doesn't force desktop to throw away what it shipped?* The decision has four simultaneously-active constituencies:

- **Mark (desktop/O-L):** "Before changing approach (e.g. making RMF responsible for promo queues) I'd like to see a task which breaks down what is wrong with the current approach taken by desktop, or what gaps we have when it comes to mobile. I would prefer to improve an existing system, rather than start again, which would either introduce another divergence, or force desktop to replace its existing implementation." Also: Mac **and Windows** already built the queue (rules by Stephen); **Chromium has a similar feature we can use**; he's "not so sure that RMFs is the solution"; wants (a) requirements, (b) what the desktop solution doesn't support, before any decision. Long-term task must include Mark, Stephen, O-L engineers.
- **Aitor (Android):** the maximalist pole — "the ideal end state is for all promos to go through RMF." Default conversation for any new promo: *Why not RMF? → can we extend RMF? → can we simplify the requirement? → bespoke only as last resort.* Motivation: bespoke-per-objective promos don't scale (regressions, inconsistent UX, conflicts, coordination overhead).
- **Chris Thelwell (product):** floated "RMFs as the promo queue — all promos (RMFs as they are today, Widget promos, Dots on menu etc etc) run as RMFs so they can be controlled remotely and inherit the queuing logic (which would need extending)"; likes the direction but procedurally wants requirements-first then a TD. His long-term feature list from the main task: modal sheets as RMFs?, supporting the necessary rules **including disabling**, standard approach to promo **measurement** (stretch). Trade-off axes he named: remotely vs on-device; measurement (e.g. pre-set method, CTR); removal/disabling in case of issues.
- **Craig Russell (Android):** the synthesis pole — RMF today has limited surfaces, so bespoke promos keep appearing; "if every single promo was RMF driven, and RMF as a framework supported all the surfaces in the app, it could act as a global centralised coordinator **but that's some distance away from what we have today.** Both parts of the puzzle need to be supported: a centralised way of managing a promo queue, which can know about promos in surfaces beyond which is supported today, **and** a way of tying into that remotely (e.g., using RMF)."
- **Cristian (Apple, project advisor):** end goal is "simplifying the conversations, coordination and management with a **single system**. And deciding what the system will be. If we go with RMF (will be one option)…" — wants requirements, gaps, then "we share a vision, pros/cons, tradeoffs… basically a **contract**."
- **Stephen (design, desktop rules author):** the queue should **delay, not suppress**; three legs — documentation/guidelines, technical foundation, process. **Abhishek (product):** promo *owners* need visibility when their promo is delayed (impression accounting). **Marcos (Apple):** whatever we pick must become the paved road, or bespoke promos keep appearing (enforce via docs + ship-review question + optional CI guardrails).

A recommendation that ignores any of these framings will stall. The deliverable must therefore be an **evidence-backed evaluation against an agreed requirements list**, not an architecture pitch.

## 2. The option space (candidates to evaluate — no others unless evidence demands)

- **Option A — RMF becomes the promo queue.** Every promo is an RMF message; RMF gains whatever it lacks (surfaces, multi-message scheduling, priorities, frequency rules, faster triggers). Full remote control: content, targeting, kill, sequencing all in the config repo. Client renderers become thin.
- **Option B — Client-side promo queue is the system; RMF is one registered input.** Extract and evolve macOS `PromoService` into a shared Apple package, build iOS adapters/contexts, let Android build/mirror the contract, and keep Windows's twin. This is substantial future work: the current iOS launch-modal group cannot be wrapped as one `InternalPromo` without new eligibility/result/active-visibility/dismissal contracts, while per-provider registration requires broader migration. Remote control comes from privacy-config flags per promo + RMF for the subset that is remote content.
- **Option C — Layered/combined ("RMF schedules content; the queue arbitrates surfaces").** Bartosz's framing, Craig's "both parts," and the *de facto* Android precedent (Fire-Mode: native tab-switcher banner rendered locally but keyed to RMF's active-message state, inheriting its matching/exclusion rules). Promos migrate to RMF *for scheduling/content/kill* wherever possible; the client queue remains the arbiter of *when/where anything shows*, covering non-RMF promos and enforcing cross-promo rules RMF doesn't have.
- **Option B+/C variant worth pricing: remotely-configurable queue rules.** Keep arbitration client-side but move the queue's *policy* (promo list order, cooldown intervals, per-promo enable/disable, impression caps) into remote config (privacy config subfeatures — note `iOSPromoQueueSubfeature` already exists — or a small dedicated config). This answers "removal/disabling remotely" without migrating content to RMF.

## 3. Hard facts to reason from (verified in code Jul 10, 2026 — re-verify what you rely on)

**About RMF (full detail + citations in `iteration_2_research.md` §2.7/§4 and its output report):**

1. **Single-scheduled-message architecture:** the store keeps exactly ONE `scheduled` message at a time **across all surfaces** (`RemoteMessagingStore.saveProcessedResult` marks other scheduled messages `done`). An NTP card and a modal cannot be live simultaneously. Any "RMF as queue" design starts with reworking this.
2. **Priority = config-file order**, first-match-wins per evaluation; no priority field, no severity/context model, no cross-message frequency caps, no start/end dates (campaigns end by editing the config), no impression caps; `dismissAfterDaysShown` and iOS-only `after_idle` trigger are the only display conditions. Dismissal is permanent.
3. **Evaluation latency:** rules re-evaluate on config download / 24h invalidation / dismissal-invalidation; iOS refreshes on foreground + 4h background task, macOS every 30 min. Event-driven promos ("right after the user burns tabs") either accept up-to-a-day lag (Chris accepted this once, for Fire Mode), get a client-side observer hack (Android's self-retire pattern), or need a trigger-extension to RMF.
4. **Surfaces are client-hardcoded per template:** iOS = NTP card (banner templates) + modal (`cards_list`, consumed *through* the ModalPromptCoordination queue as What's New); macOS = NTP + tab-bar (survey-only renderer) with `dedicated_tab` declared but unrenderable. No badges/dots/pills/settings-rows/list-headers anywhere. Adding a surface = schema enum + OptionSet bit + per-platform provider + renderer/consumer + pixels/tests; the existing numeric bitmask does not inherently require a Core Data migration.
5. **Attributes/actions are release-gated** (client-hardcoded vocabulary; unknown attrs fall back per-config `fallback`); in-app navigation actions already exist on iOS (`sync`, `settings`, `pir.main`, …) — the "can't open Settings" objection was wrong. Remote images exist on iOS and Android; bundled `placeholder` art is release-bound.
6. **Limited experiment integration:** RMF supports `expVariant` and stable per-message percentile; privacy-config cohort flags are excluded from `allFeatureFlagsEnabled`. Measurement = shown/dismissed/action pixels per message (CTR computable), suppressible per message.
7. **Privacy posture:** RMF is a **static CDN config, identical for everyone**, evaluated on-device (`remotemessaging/config/v1/*-config.json` on `staticcdn.duckduckgo.com`) — no per-user server decisions. Any Option-A extension must preserve this (that's a requirement, not a nice-to-have).
8. **Localization:** translations inline per message in config JSON (heavy duplication; the live iOS config duplicates one survey ×8 locales as separate rules). Scale this to ~80 promos and the config becomes very large — quantify (§5 RQ3).

**About current client-side coordination and the Option-B candidate:**

9. macOS `PromoService` remains app-target code in `macOS/DuckDuckGo/Promotions/`: fixed promo list, array-order priority, `Internal` (queue-controlled show/hide) vs `External` (observed visibility — RMF's slot) promos, context model (`.global`/`.newTabPage`/`.webPage`/`.fireWindow`), severity-based conflicts, per-`initiated` global cooldowns, `PromoHistoryStore` (shown/dismissed/nextEligible/actioned), debug menu, and tests. RMF integrates as observation-only `ExternalPromo`s. It does not make RMF wait, coordinate two external promos, or roll back feature state when `.noChange` retracts an internal promo.
10. **iOS iteration 1 is not this queue:** it preserves `PromoCoordinationService`, `ModalPromptCoordinationManager`, all seven providers, and `PromptCooldownManager`. A small app-level coordinator grants NTP/modal permits; once a modal commits it is never programmatically hidden, and RMF waits without shown/dismissed accounting. PR 1 added disabled-by-default `FeatureFlag.promoPresentationCoordination`, now housed in the `FeatureFlags-iOS` package and mapped to `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination`; remote enablement remains a separate rollout decision.
11. **Windows has its own queue** (shipped Q1 2026, "Windows: Implement promo queue", rules from Stephen's doc; a "Changes to sync for Windows <> macOS implementations" task existed) — different codebase, parallel implementation. "One system across platforms" can therefore mean *one spec + per-platform engines* (today's reality) or *one shared implementation* (only Apple platforms can literally share Swift).
12. **Android has no promo queue**; it has NTP-level priority rules (Onboarding → RMF → other CTAs, per Cristian) and just shipped the Fire-Mode-via-RMF pattern. The observed Android clash that motivated iteration 1 suggests a regression in those rules, not a missing design.
13. **Chromium prior art** (Mark's pointer): Chrome's `feature_engagement` / In-Product Help — a **client-side, config-driven engine**: features declare event-based triggers, rate limits, and "used" events; a local database enforces caps/cooldowns; Finch (remote config) tunes the parameters. I.e. Chromium chose "config-driven client engine," not "server schedules everything." If you have web access, verify against Chromium docs/source (`components/feature_engagement/`); if not, mark as to-confirm and rely on the description here as directional.

## 4. Requirements baseline (consolidate, don't reinvent)

Build the evaluation against ONE numbered requirements list synthesized from (all reproduced in `iteration_2_research.md` §2.4): Stephen's Rules & Guidelines V1 (one Med–High interruption at a time; 1/day app-initiated; 1/hour user-initiated; one NTP message at a time; no prompts on deep-link launches; delay-don't-suppress; same-priority tie-breaking; essential-message preemption), the mobile Global Guidelines (28-day re-show, never after explicit "No Thanks", badge expiry, no promos on onboarding day, priority system), the In-product promo guidance (dismissibility, impression/day caps, hard expiry), Chris's long-term features (modal sheets as RMF?, disable rules, standard measurement/CTR), and the operational asks (owner-visible impression accounting — Abhishek; works for temporary campaigns — Fire Mode's 3-week window; paved-road/process enforceability — Marcos/kick-off item 4). Tag each **Must / Should / Nice** and note its source. This list is deliverable §A — Mark explicitly asked for it, and it's the yardstick for everything else.

## 5. Research questions

### RQ1 — What exactly would RMF need, to *be* the queue (Option A bill of materials)

Design-sketch level, each item sized S/M/L with the release-gating called out, grounded in the actual code:

- multi-message scheduling (store + processor rework away from single-scheduled-message; per-surface active message)
- a priority/severity/context model (where does it live — config schema? how does config-order priority coexist?)
- cross-message frequency rules (1/day app-initiated, 28-day per-feature cooldowns, impression caps, hard expiry — none exist today)
- surface registry: enumerate the surfaces from the iteration-2 inventory that RMF would have to learn (modal sheet, settings rows, list section headers, menu rows, badges/dots, pills/toasts, tab-switcher…) and what "a remote badge" even means (content vs. just visibility control)
- event-driven triggers (client-side rule re-evaluation on named events, Chromium-style, vs. accepting 24h latency)
- native-state matching attributes at scale (every promo's eligibility conditions become matcher plugins — count them from the iteration-2 inventory; each is a release)
- measurement standardization (are shown/dismissed/action pixels + `metrics.state` enough for "standard CTR"?)
- config-repo scale + process (config size with ~80 promos × translations; review/ownership model — today's matcher-proposal process is documented in `iteration_2_research.md` §2.6; would need an AOR)
- offline/first-launch behavior (RMF needs a fetch; what shows before the first config download?)
- what happens to Windows/macOS queues (rip out? wrap RMF as a feeder into them? — Mark's divergence test)

### RQ2 — What the client-queue-as-system would need (Option B bill of materials, same rigor)

- per-promo remote disable + remote ordering/cooldowns (privacy-config subfeature pattern vs. a small dedicated config — price both; note kill granularity and propagation latency vs. RMF's config pull)
- covering remote *content* needs: which promos genuinely need remote copy/imagery/targeting (from the iteration-2 classification) — those still want RMF; Option B must design a bidirectional permit bridge rather than assume macOS's observation-only `ExternalPromo` seam is sufficient
- Android parity: effort to build/mirror the queue on Android (nothing exists; Kotlin twin of the spec, not shared code)
- measurement: queue-level standard pixels (shown/dismissed/delayed) + owner-visible delay accounting
- process: same paved-road story as A (the queue is only a system if new promos actually register)
- the honest gap list Mark asked for: **what the desktop solution doesn't support today** — remote content, remote per-promo kill, cross-platform single implementation (Windows is parallel code), impression caps/expiry enforcement (history exists, policy doesn't), owner dashboards, FE/web surfaces on desktop NTP, and iOS/Android coverage. Iteration 1 only supplies a narrow iOS NTP/modal permit seam, not PromoService coverage.

### RQ3 — The combined model (Option C): define the contract precisely

This is a strong proposal (it matches Craig's "both parts," the Android precedent, and the revised iteration-1 permit principle while letting desktop keep its queue) — so give it the most design attention, *without* presupposing it wins the evaluation:

- **Layering rule:** RMF = remote scheduling/content/targeting/kill for anything remote; queue = the only component that decides *visibility now* (arbitration, frequency, priority, context/severity), for RMF and non-RMF promos alike. Verify the seam works beyond the NTP card: how does a hypothetical RMF modal/badge enter the queue — one `ExternalPromo` per surface (macOS pattern) or per message?
- **The Android hybrid as a template:** native surface rendered locally, *keyed to RMF active-message state* (inherits matching/exclusion/kill). Which iteration-2-inventory promos fit this pattern (remote control without new RMF renderers)?
- **Decision tree for new promos** (formalize Aitor's ladder within the contract): RMF off-the-shelf → RMF with small extension (attribute/action via the proposal process) → simplify the requirement → hybrid (native render keyed to RMF) → queue-registered client promo (with remote disable) — bespoke unqueued = never.
- **Interface obligations both ways:** what RMF must add even in Option C (modal-sheet surface eventually — CT says "at some point"; possibly per-surface scheduling) and what the queue must add (remote policy knobs per §2's B+ variant; owner impression accounting; Android implementation).
- Failure modes: double-accounting of shown/dismissed between the two systems; RMF's single-message bottleneck starving queue-registered RMF surfaces; divergence between platforms' promo lists.

### RQ4 — Evaluation

Score A / B / C (and the B+ remote-rules variant) against the RQ0 requirements list (§4) on: functional fit, effort-to-parity (S/M/L per platform), migration risk, release-coupling, privacy posture (static config, no per-user server state, cohort-free), offline behavior, cross-platform consistency without forcing desktop rewrites (Mark's veto), org/process fit (paved road, ownership/AOR, review flow), and reversibility. Note where candidates are *complementary rather than exclusive* — the honest possibility that "A eventually, via C, starting from B" is a sequencing statement, not a compromise. Include a **migration narrative** per option (what happens to the ~80 iOS promos, the 6 launch modals, desktop's queues, Android's nothing) and each option's first shippable increment.

### RQ5 — Recommendation memo skeleton ("the contract", per Cristian)

Produce the skeleton the humans will fill: proposed end state + explicit non-goals; the decision tree for new promos; required RMF extensions (ranked, sized, with the matcher/surface proposal process named); required queue extensions; ownership proposal (AOR; who approves new promos/matchers); measurement standard; enforcement mechanics (ship-review question, docs, CI guardrail options from kick-off item 4); open product questions (e.g. "is ≤24h latency acceptable for event-driven promos as a class, or per-case?"); and the list of scoped follow-up projects with rough estimates — this last item is literally the "Scope follow-up projects" task (`1216396156310212`).

## 6. Method notes

- Ground every capability claim in `file:line` (framework: `SharedPackages/BrowserServicesKit/Sources/RemoteMessaging/`; iOS app integration: `iOS/DuckDuckGo/`; macOS queue: `macOS/DuckDuckGo/Promotions/`; config repo: `schemas/`, `live/`, `templates/`). `iteration_2_research_appendix.md` already carries most citations — Part 1 (RMF capability map incl. the single-scheduled-message store, surface matrix, live configs) and Part 2 (iOS promo inventory + macOS `PromoServiceFactory` registrations + preliminary classification). Reuse, spot-check, extend — don't re-derive.
- Where a claim rests on Asana context (positions, product intent), cite this doc/§ and mark it "reported, not verifiable in code."
- Effort classes: calibrate S against Android's Fire-Mode TD (1 action + 2 attributes + hybrid banner ≈ days), M against "new RMF surface" (schema+client+renderer+store), L against "multi-message scheduling rework" / "Android queue from scratch".
- If anything you find contradicts the §3 facts (e.g. multi-message support quietly landed), the contradiction is a headline finding — say so loudly.

## 7. Out of scope

- Re-running the iteration-2 promo inventory or capability map (consume their outputs).
- Committing to a recommendation on behalf of the team — you prepare the evaluation and the memo skeleton; Mark/Stephen/Cristian/O-L/O-A make the call in the TD.
- Any Asana writes; any code changes.

## 8. Asana link ledger (for humans)

- Define future approach: `https://app.asana.com/1/137249556945/task/1216396156310211` · Scope follow-ups: `…/task/1216396156310212` · Main task: `…/task/1214299397742171`
- Positions: Kick-off `…/task/1214300205792376` · DRI<>PA (Mark, Jul 8) `…/task/1214300205792372` · Fire Mode thread (Chris↔Aitor↔Craig, Jun 30) `…/task/1216107774194120` · Jul 9 gaps thread on main task (Pablo/Cristian/Craig)
- Requirements: Stephen's Rules V1 `…/task/1213119765994047` · Mobile Global Guidelines `…/task/1214130328245985` · In-product promo guidance `…/task/1210875235779852`
- Prior art: macOS queue `…/task/1208645854909942` · Windows queue `…/task/1212808524770775` · Android Fire-Mode RMF TD `…/task/1216213068497872` · Android conflict task `…/task/1216146972756295` · RMF matcher proposals `https://app.asana.com/1/137249556945/project/1207619243206445/list/1207619413684520`
