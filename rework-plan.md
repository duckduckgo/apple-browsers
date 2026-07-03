# Plan — Contextual UTI (part 1): a persistent UTI that *is* the native flow, just richer

**Status: PARKED (2026-06-30)** — design converged + **twice red-teamed**, plan complete, **no code written**.
Paused pending **#5596 (web-view-immediate)** merging: that port deletes the transitional *swap glue* (see §10),
so rather than build glue we'd immediately bin, we resume on the web-view-immediate base. Pete is moving to a
different worktree meanwhile. **Resume trigger: #5596 merged.**
**Base:** clean `origin/main` `dc6da9d607` (branch `pete/ios/uti-contextual-part-1`, reset; prototype preserved
at `uti-part-1-prototype` + PR #5602). **Standalone — no dependency on #5596** (forward-compatible).
**Grounded in:** the 5 deep-dive references (`review-artifacts/deep-dives/01–05`) + `understanding.md`.

> This is a **build**, not a delete: on clean main the *pre-submit* contextual UTI does not exist (only the
> active-chat UTI does). We add the pre-submit capability **without** ever introducing the prototype's soup.

---

## 1. Goal
Behind the kill-switch flag, replace the basic native input box on the **presubmission** contextual Duck.ai
sheet with the unified toggle input (UTI), as a **drop-in over the existing native flow**. Parity bar: open at
`.medium`, keyboard down, expanded bar (not the collapsed pill), expand to `.large` on first submit. Subsequent
behaviour = the active-chat UTI on main. Nav-chip re-attach + attach-menu + voice-tap are **out** (later parts).

## 2. The converged design (one breath)
**One UTI** is mounted at sheet level and **persists** across the native→web swap (seamless, no input jump).
Pre-submit it is **unbound**; its first submit rides the **existing native submit road**
(`handlePromptSubmission` → `.submitPrompt` effect → web-VC readiness queue), which we **widen to carry the
UTI's rich payload** (model/tools/reasoning/images/files). The web view then **binds** the UTI; subsequent
prompts go through the bound user script — exactly the active-chat path on main. The page-context chip is fed
from **`sessionState.chipState`** pre-submit and hands off to the UTI's `chipViewModel` at bind (the existing
`initialUTIAttachment` seed). Model-chip visibility derives from a **host adapter reading live `frontendState`**.

## 3. Ground truth that constrains the design (from the dives)
- **`frontendState` is the synchronous single source of truth**, zero consumers outside its file. Safe to read
  for phase; **cannot** derive `chipState`/context/detent from it.
- **The web view loads from sheet open**; `webVC.submitPrompt` already queues (`pendingPrompt`, gated on
  `isPageReady && isContentHandlerReady`, `:201`) — the proven first-prompt buffer.
- **On main the contextual UTI is post-submit only** — embedded in the web VC, `hasSubmittedPrompt = true`,
  model chip **permanently hidden** (`host == .contextualChat`, coordinator `:2358`).
- **The unbound submit silently drops** — coordinator unbound branch (`:1959`) calls a `delegate` the contextual
  host never sets. Must be wired.
- **The page-context chip is independent of `frontendState`**; the nav re-attach fork (`notifyPageChanged`
  early-return `:211`) is part-3 — do not disturb.

## 4. Target architecture

### 4a. Persistent sheet-level UTI mount
- Mount one UTI at sheet level (expanded bar, keyboard down — call `showExpanded(activatesInput: false)`).
- Re-anchor the content-container bottom to the UTI top; add the `superview ===` **survival guard** in
  `transitionToWebView()` so the UTI is NOT torn down at the swap (reference: prototype `mountAtSheetLevel`).
- The coordinator stays **UNBOUND until the first submit** — do NOT let the web view auto-bind it at sheet open.
  This is what makes the first prompt reliably take the unbound→funnel path (§4b) and honors the pre-submit-unbound
  parity bar. It **binds right after** the first submit; subsequent prompts then go direct via the bound script.

### 4b. First prompt = ONE funnel (the widened native flow) — no separate buffer
**Verified contextual-only (2026-06-30):** `contentHandler.submitPrompt` is called *only* by the contextual web
VC (`AIChatContextualWebViewController.swift:209/:366`). The full Duck.ai tab instantiates `AIChatContentHandler`
(`TabViewController.swift:706`) but **never calls `submitPrompt`** on it — it submits via the omnibar UTI straight
to `userScript.submitPrompt` (`UnifiedToggleInputCoordinator.swift:1957`). So widening the funnel is
**contextual-only; the full tab is untouched.** (Resolves the Codex/Claude disagreement — Claude was right.)

**The widened funnel is the DURABLE primary flow (Pete, 2026-06-30).** The basic native input is only the
flag-OFF (kill-switch) fallback, destined for removal once the UTI ships unflagged — then the funnel is the
**sole** path (the UTI's first prompt keeps using it). So widening it is a durable investment, not a transitional
hack. *Part-1 caveat:* flag-OFF must still run the native box exactly as today → keep the rich params
**optional/defaulted `nil`** so flag-off is byte-for-byte unchanged (kill-switch safety), and flag-on is the
widened flow.

- **Split the first submit into FLIP + DELIVER — do NOT widen `SheetEffect`/session-state/SheetVC** (red-team v2
  C1: that threads model/tools/images/files through UTI-ignorant lifecycle/UI layers across ~9 sites). On the
  unbound first submit, `coordinator.delegate = contextualHost` receives it and the host does two things:
  1. **Flip (lifecycle):** `sessionState.beginChatForUTISubmission()` — flips `frontendState` (native→web swap +
     expand + chip-hide) and **does NOT emit `.submitPrompt`** (so nothing double-delivers). **KEEP this method**
     (v2 reversed the earlier decision to delete it).
  2. **Deliver (the one buffer):** the host calls a **single rich `webVC.submitPrompt(rich, pageContext: frozen)`**
     overload that reuses the web VC's **existing readiness queue** (`pendingPrompt`, gated on
     `isPageReady && isContentHandlerReady`, flushed by `submitPendingIfReady`). Widen ONLY the web-VC-and-below
     layers: `webVC.submitPrompt` (`:201`) + its pending storage (`String?`→rich) + `submitPendingIfReady`/
     `submitPromptNow` (`:344/:363`) + `contentHandler.submitPrompt` (`:256`) → the rich `userScript.submitPrompt`
     (`:335`). Add an optional explicit `pageContext` there (`pageContext ?? attachedPageContextProvider?()`) so the
     **frozen** snapshot rides through (additive; omnibar passes nil → provider, unchanged).
- **The web VC queue is the ONLY buffer.** No host buffer, no `PendingFirstPrompt`, no provider-swap, **no
  `.submitPrompt`-effect widening.**
- **Telemetry (red-team v2 C2):** the unbound contextual submit must NOT fire the dead `promptDelivery` (`:1961`)
  and must record the correct `frontendDeliveryPath` (it goes via userScript, NOT `.urlAutoSubmit` `:1924`).
  The delivery pixel fires **once**, from the webVC path (`:210`).
- **Rapid second submit (red-team v2 Codex):** because the UTI persists (unlike the vanishing native box), the user
  can submit again during the loading window → overwrite/loss/out-of-order in the queue. **Gate the UTI submit
  until the first prompt is delivered.**
- **Why first ≠ subsequent:** unbound first submit → flip + queue (above). Subsequent (bound) prompts go direct via
  `userScript.submitPrompt(rich)` — never early, never buffered. One buffer; the first prompt uses it, the rest don't.

### 4c. Model-chip visibility — host adapter, live phase, drift-proof
- New `UnifiedToggleInputHostAdapter { var isPreSubmitPhase: Bool }` (shared module); contextual conformance
  `ContextualChatHostAdapter` (ContextualMode) reads `sessionState.hasActiveChat` live. Coordinator holds it
  **`weak`**; the host **retains it strongly**.
- Replace the permanent hide term (`:2358`) with `host.isContextualChat && !hostAdapter.isPreSubmitPhase`.
- **Re-trigger (NO publisher exists — red-team C3):** `frontendState` is `private(set)`, not `@Published`, so
  there is nothing to subscribe to. Drive it **synchronously**: the host calls `handlePromptSubmission` on the
  first submit (flips `frontendState`), then synchronously calls `coordinator.updateModelChipVisibility()` on the
  same call path. The adapter reads live `frontendState` (rebind-proof — rebind clears `hasSubmittedPrompt` but
  not `frontendState`); `hasSubmittedPrompt` (set by `markActiveChatPromptSubmitted` before the fork) gives the
  immediate hide. Clean replacement for the `hasSubmittedContextualPrompt` latch — no subscription, no latch.
- Boot (red-team v2 H1): `.contextualChat` stays **bare** (no associated value → preserves `host ==` at ~11
  sites). Pass the pre-submit-vs-active boot decision as **static init args** — the host knows `hasActiveChat()`
  before it builds the coordinator (a `let` inside the host's own init, so a live adapter can't be consulted
  mid-init). The **live adapter is for the runtime re-trigger ONLY** (model-chip after submit/rebind); the
  immediate hide is `hasSubmittedPrompt`, the adapter is purely the rebind-survival backstop (red-team v2 M2).

### 4d. Context chip — `sessionState.chipState` pre-submit, hand off at bind
- Pre-submit: feed `viewState.chipState` into the UTI bar's chip view (bypass the UTI's `chipViewModel`).
- **Provider-wiring resolution (the consequence of the submission asymmetry):** subsequent bound submits pull
  context from `attachedPageContextProvider` (UTI host `:184` → `chipViewModel`). So the chip *source* transitions
  with phase, and context-for-submit follows it at each phase — **no mismatch**:
  - Pre-submit: chip = `sessionState.chipState`; first-prompt context = `sessionState.chipState` (read by
    `handlePromptSubmission`). **Match.**
  - At bind: seed `chipViewModel` from `sessionState`. **NOTE (red-team H1):** the existing `initialUTIAttachment`
    seed is read at **host construction**, not bind (`AIChatContextualSheetCoordinator.swift:336/356`), so it
    misses late context — **re-seed explicitly at bind**, don't rely on the construction-time read.
  - Post-submit: chip = `chipViewModel`; subsequent context = `chipViewModel` (via provider). **Match.**
  - Net: chip source is sessionState pre-submit (drop-in) → chipViewModel post-bind (as main), bridged by an
    explicit **re-seed at bind**. *(Validate the handoff has no gap/flicker during slice 5.)*

### 4e. What this design ELIMINATES (never introduce)
`PendingFirstPrompt` host buffer · `flushPendingFirstPromptIfNeeded` · `hasNotifiedFirstPrompt` ·
`hasSubmittedContextualPrompt` latch · **the `.submitPrompt`-effect widening** (red-team v2 C1). The web VC queue
(reached via a direct rich `webVC.submitPrompt`) + the adapter replace them.
**KEEP `beginChatForUTISubmission`** (flip-only) — v2 reversed the earlier delete; it's the lifecycle flip that
lets the host deliver the rich payload itself without double-sending.

### 4f. Remaining red-team-v2 must-dos (fold into the slices)
- **Reset must `coordinator.unbind()` + clear the script identifier** on New-Chat / fire / timeout — else the
  *next* first prompt takes the BOUND branch and never flips `frontendState` (v1's invisible-chat bug, post-reset).
  Plus clear pending-first-submit, attachments/tools/text, and re-seed the chip.
- **Shown-but-unbound gating:** while unbound, hide/disable the active-chat toolbar actions (Customize-Responses,
  voice, generation controls) and route `DidChangeHeight` to the **sheet-level mount** owner, not the web VC
  (`DidChangeHeight` is a *mandatory* delegate method — the mount's height signal, not a no-op).
- **Deferring the bind also defers** `attachedPageContextProvider`/`onPromptSubmitted`/`restoreLastUsedModel`
  (wired at web VC `:412`). **Wire model-restore + the chip's model label pre-submit** independently, so the
  pre-submit model chip isn't empty/cached until first submit.
- **Delegate conformance:** `coordinator.delegate = host` requires the full `UnifiedToggleInputDelegate` (~9
  mandatory methods, only 3 defaulted); implement them (mostly contextual no-ops) + keep the bound-submit-drop guard.
- **Failure-path drain** (slice 7): the web VC queue is now the *sole* first-prompt buffer — add a timeout /
  error-clear if readiness never fires.

## 5. Implementation slices (each: build + sim light/dark + tests before the next)
1. **Flag + gate carry-forward** — `aiChatContextualUnifiedToggleInput` + subfeature + `ContextualUnifiedToggleInputFeature`
   AND-gate (iPhone-only/grant-gated). No behaviour yet. Tests: gate matrix.
2. **Host adapter + model-chip derivation** — protocol + `ContextualChatHostAdapter`, coordinator consults it,
   bare `.contextualChat`, the phase-change re-trigger. Tests: chip shown pre-submit / hidden active /
   **stays hidden across a simulated rebind** / omnibar unaffected.
3. **Persistent sheet-level mount** — mount expanded/keyboard-down, survival guard, content re-anchor. Sim parity
   (medium, keyboard down, expanded bar). No submit yet (or native submit still).
4. **Extended submit path** — widen `.submitPrompt`/`webVC.submitPrompt`/`contentHandler.submitPrompt` (optional
   params) + wire `coordinator.delegate`; unbound submit → `handlePromptSubmission(rich)`. Tests: first submit
   delivers rich payload once via the queue; native box path unchanged (nil params); no double-send.
5. **Chip source + handoff** — `sessionState.chipState` pre-submit, `initialUTIAttachment` seed at bind. Tests +
   sim: chip parity pre-submit; context matches on first and subsequent prompts.
6. **Reset completeness** — New-Chat/fire/timeout return the persistent UTI to clean pre-submit (unbound, chip
   shown). Tests for each reset path.
7. **Failure path** — stuck-first-prompt policy in the web-VC queue (timeout/error-clear).

## 6. Tests (regression-lock the bug class)
- **Rebind-stays-hidden** (the original bug, locked). · First submit flips `frontendState` synchronously +
  delivers rich payload exactly once via the queue. · Native-box path byte-for-byte unchanged (nil rich params).
  · Omnibar model-chip unaffected (no adapter). · Reset completeness across the 3 paths. · Provider/chip context
  parity on first vs subsequent prompts.

## 7. Watch-outs (landmines)
1. **Model-chip hide timing** — needs the phase-change re-trigger (§4c), else the chip lags a runloop.
2. **Signature-widening reach** — optional/defaulted params; **verify whether `AIChatContentHandler` is shared
   with the full Duck.ai tab** (overload vs additive).
3. **Unbound-delegate silent drop** — wire `coordinator.delegate = host` (§4b) or the first prompt vanishes (`:1959`).
4. **Survival guard + re-anchor** — or `transitionToWebView()` tears the UTI down.
5. **Failure path** — no timeout/drain on main; the queued first prompt is the conversation start.
6. **Do-not-disturb** — `notifyPageChanged` early-return `:211`, `canPushToFrontend()` `:416`, the UTI chip
   publishers / `suppressExternalContextUntilNextAttach` guards (part-3). Preserve `frontendState`'s 4 internal uses.
7. **Adapter init ordering / weak-ref retention** — adapter built before the coordinator's init boot block;
   coordinator holds it weak, host retains it strong; no retain cycle.

## 8. Open questions (resolve during slices)
- Is `AIChatContentHandler.submitPrompt` shared with the full Duck.ai tab? (→ additive vs overload)
- Exact failure-path policy (timeout value? error surface? clear + re-enable input?).
- Chip-source handoff at bind — any flicker between `sessionState.chipState` and `chipViewModel`?

## 9. Carry-forward + do-not-disturb
- **Carry:** flag + subfeature + AND-gate, voice availability wiring, the test set; reuse the
  `initialUTIAttachment` seed. **Reference patterns** (prototype): `coordinator.delegate = self`, mount survival
  guard, content re-anchor.
- **Untouched:** the omnibar path; the active-chat UTI's post-submit behaviour; the context nav-fork (part-3).

## 10. Forward-compat with #5596 — and the PARKED resume guide
**Decision (Pete, 2026-06-30): PARK until #5596 (web-view-immediate) merges, then build on it.** Web-view-immediate
shows the web view from sheet open, which **deletes the swap glue** — so we don't build glue we'd immediately bin.

**Deleted at the convergence (transitional glue — do NOT gold-plate if built early):** `transitionToWebView()` ·
the `superview ===` **survival guard** · the content-bottom **re-anchor** · the `viewState.content`
`.nativeInput`/`.webView` fork + `rebuildViewState`'s native-vs-web mapping · the native input box itself (it's
the flag-off fallback). **Expand** (`.medium→.large`) is a *separate* detent UX choice — survives unless we open `.large`.

**Survives untouched (the durable core — implement THIS on the web-view-immediate base):** persistent UTI mounted
with the web view (no survival guard needed once there's no swap) · the **flip** `beginChatForUTISubmission`, now
**chip-only** (drives model-chip hide + `hasActiveChat`, not a content swap) · **direct delivery**
`host → webVC.submitPrompt(rich)` into the web-VC queue (the one buffer) · the host-**adapter** (immediate
`hasSubmittedPrompt` + live-`frontendState` rebind backstop) · chip from `sessionState.chipState` re-seeded at bind ·
**unbound-until-first-submit** · all red-team-v2 must-dos (§4f).

**On resume:** rebase the worktree onto merged #5596 → implement the durable core on the web-view-immediate sheet
(skip the swap glue) → the §5 slices minus slice 3's swap/re-anchor work.
