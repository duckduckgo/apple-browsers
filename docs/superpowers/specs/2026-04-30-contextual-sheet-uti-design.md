# Contextual Chat: Native UTI Replacement — Design

- **Asana:** https://app.asana.com/1/137249556945/project/1214157224317277/task/1213726441787520
- **Branch:** `jacek/contextual-sheet-uti`
- **Feature flag:** `unifiedToggleInput` (existing)
- **Date:** 2026-04-30

## 1. Goal

Replace the duck.ai *frontend-rendered* composer at the bottom of the contextual full-screen chat (`AIChatContextualWebViewController`) with the native **Unified Toggle Input** (UTI) — the same component used in full-tab duck.ai and the omnibar. Add a page-context attachment chip to UTI to preserve the "Attach page content" affordance the FE composer offers today.

All behavior gated behind the existing `unifiedToggleInput` feature flag. With the flag off, the contextual chat continues to render the FE composer exactly as today — no behavioral change.

## 2. Non-Goals

- **No change to the half-sheet input** (`AIChatNativeInputView`). The initial native rounded-pill at the bottom of the bottom-half sheet stays as-is.
- **No move of UTI into the AIChat shared package.** UTI stays in the `iOS/DuckDuckGo` target. Package extraction is a separate, larger refactor.
- **No new "auto-attach" preference UI.** The half-sheet's existing "Ask about page" toggle remains the source of truth for whether the first prompt carries page context.
- **No support for the FE composer and native UTI being shown simultaneously.** Either-or, gated by the flag (and the corresponding `nativeInput` URL param the FE honors).

## 3. Surfaces affected

| Surface | Today | After |
| --- | --- | --- |
| Initial half-sheet (`AIChatContextualSheetViewController`) | Native rounded-pill input + quick-actions row | Unchanged |
| Post-submit chat (`AIChatContextualWebViewController`) — bottom composer | FE-rendered composer, with FE "Attach page content" button | Native UTI with page-context chip (flag on) / FE composer (flag off) |
| Full-tab duck.ai composer | UTI | Unchanged |
| Omnibar UTI | UTI | Unchanged |

## 4. UTI feature gating in this context

When UTI is hosted inside `AIChatContextualWebViewController`, only the elements that make sense in a chat-continuation surface are shown.

| UTI element | Behavior in contextual chat |
| --- | --- |
| Search ↔ Duck.ai toggle | **Hidden** (always Duck.ai here) |
| Image attachments strip + leading attach button | Kept |
| Tools / RAG menu (leading "tools" button) | Kept |
| Reasoning picker | Kept |
| Model selector chip | Kept |
| Voice button | Kept |
| **Fire button on UTI toolbar** | **Hidden** (the contextual chat top toolbar already has fire) |
| Submit arrow | Kept |
| Suggestions / history overlay (`UnifiedInputContentContainerViewController`) | **Hidden** (no relevance in chat continuation) |
| Floating submit (anchored to `keyboardLayoutGuide`) | **Hidden** (no omnibar to overlay) |
| Expand / collapse animation | **Always expanded** (sheet already gives it space) |
| **Page-context chip** *(new)* | **Visible per rules below** |

## 5. Page-context chip — behavior

A new horizontal row inside the UTI card, slotted **between the text-entry surface and the image-attachments strip** (so the visual order top-to-bottom is: toggle → text-entry → page chip → image strip → toolbar). The chip is the only attachment-style affordance the row holds; it's a single binary placeholder, not a strip of N items.

### 5.1 Visibility rule

The chip is **hidden** iff *the originating tab's currently-displayed URL equals the URL of the page already attached to the conversation*. Otherwise the chip shows the "Attach page" placeholder.

Equivalent state machine:

```
inputs:
  originatingURL  ← URL of the originating tab's WKWebView (live)
  attachedURL     ← URL of the most recent page-context attached to the conversation (nil if none)

chip state:
  if originatingURL == attachedURL  → hidden
  else                              → placeholder ("Attach page")
```

### 5.2 Triggers

- **Arrival from half-sheet, "Ask about page" was on** → first prompt carries page context, `attachedURL = originatingURL` → chip hidden.
- **Arrival from half-sheet, "Ask about page" was off** → no context attached, `attachedURL = nil` → chip placeholder.
- **User taps placeholder** → trigger context collection on the originating tab via `AIChatPageContextHandler.triggerContextCollection()`, push to FE via the existing `submitAIChatPageContext` user-script message, set `attachedURL = originatingURL` → chip hides.
- **Originating tab navigates to a different URL** (observed via the existing KVO + `TabViewController.notifyPageChanged()` path → coordinator publishes new URL) → chip recomputes; if the new URL differs from `attachedURL` → chip shows placeholder again.
- **Auto-attach on (i.e. half-sheet "Ask about page" toggle is on as a session preference)** → on page-change, the system attaches silently (re-uses `triggerContextCollection` + `submitAIChatPageContext`); chip stays hidden.

### 5.3 Submission behavior

The chip is **independent of submit**. Tapping the chip attaches the page now (via the same path the FE button uses today). The submit arrow on the UTI toolbar continues to send the prompt only. This matches the FE composer's current per-turn semantics.

### 5.4 Visual

Reuses the same chip styling as the half-sheet's "Ask about page" quick-action pill (`AIChatContextualQuickAction.askAboutPage`) — single rounded pill with leading icon and label. Tap target is the entire pill. No detach affordance on the pill itself; detach is implicit via the page-change rule. (We don't currently support "I attached, but I want to un-attach the same page" — neither does the FE today.)

## 6. Frontend coordination

The duck.ai FE renders its own composer based on `setDisplayMode(.contextual)`. To suppress it without inventing a new display mode (and the matching test matrix), we use a **load-time URL query parameter**.

- New constant: `AIChatURLParameters.nativeInputName = "nativeInput"`.
- `AIChatContextualWebViewController` appends `&nativeInput=1` to the duck.ai URL **only when** `featureFlagger.isFeatureOn(.unifiedToggleInput)` is true at presentation time.
- The FE team owns the FE-side change to honor this param and skip rendering its bottom composer when present.
- No race window — the FE knows from first paint.

Flag off → no param → FE renders its composer → no native UTI → today's behavior.

Flag on → param present → FE skips composer → native UTI installed at the bottom.

## 7. UTI refactor — what gets generalized

The UTI is currently fused with `MainViewController` / `MainViewCoordinator`. The minimal refactor scope to make it sheet-hostable:

### 7.1 Introduce a host abstraction

A new `UnifiedToggleInputHost` enum (name TBD during impl, but the *concept* is fixed) parameterizes the coordinator at init. Cases:

- `.omnibar` — current behavior, fused to `MainViewController`.
- `.contextualChat(originatingTabURLPublisher: AnyPublisher<URL?, Never>, pageContextHandler: AIChatPageContextHandler, prompts: AIChatNativePromptSubmitting)` — what we're adding. Note: the contextual host also carries the dependencies UTI doesn't otherwise have access to (originating tab URL stream, page context handler, prompt submission target).

The host context drives:

- Which `UnifiedToggleInputDisplayState` cases are reachable (sheet host never enters `.omnibar(...)`).
- Which `UTIRenderState` flags are set (`isToggleVisible`, `isFireVisible`, `isFloatingSubmitVisible`, `isSuggestionsVisible`, `isPageChipVisible`, etc.).
- Whether `MainViewController` callbacks are wired (only for `.omnibar` host).
- Where animations originate (sheet host doesn't trigger `MainViewCoordinator` navbar animations).

### 7.2 Decouple the coordinator from `MainViewCoordinator`

- The coordinator currently calls into `MainViewCoordinator.unifiedToggleInputContainer`, `navigationBarCollectionView`, and the omnibar status-background. These calls become host-conditional — only triggered for `.omnibar` host.
- The contextual host installs the UTI's view controller into a sheet-owned container; no navbar animations.

### 7.3 Add `UTIRenderState` flags

- `isPageChipVisible: Bool`
- `isToggleVisible: Bool` (currently always true; false in contextual host)
- `isFireVisible: Bool` (true in omnibar/aiTab hosts; false in contextual host)
- `isSuggestionsVisible: Bool`
- `isFloatingSubmitVisible: Bool` (already exists but always-on for omnibar; always-off for contextual)
- `isAlwaysExpanded: Bool` (true for contextual host)

The host is the source of truth — flags are derived from `(host, displayState, currentText, focus, ...)`.

### 7.4 Stub a sheet host installer

A new file `iOS/DuckDuckGo/AIChat/ContextualMode/AIChatContextualUTIHost.swift` wraps:

- Construction of the `UnifiedToggleInputCoordinator` with `.contextualChat(...)` host context.
- Installation of the UTI's view controller as a child of `AIChatContextualWebViewController`, replacing the bottom inset of the WKWebView.
- Wiring of the page-chip's tap → `pageContextHandler.triggerContextCollection()` + `submitAIChatPageContext` push.
- Wiring of submit → existing `AIChatContextualSheetCoordinator` prompt-submission path (the same path the half-sheet uses).

## 8. Data flow

### 8.1 Originating tab URL → page-context chip

```
TabViewController (KVO #keyPath(WKWebView.url))
    │
    │  webViewUrlHasChanged()  +  notifyPageChanged()
    ▼
AIChatContextualSheetCoordinator (already subscribes via pageContextHandler.contextPublisher)
    │
    │  new: re-publishes originatingURL as AnyPublisher<URL?, Never>
    ▼
UnifiedToggleInputCoordinator (.contextualChat host)
    │
    │  combines originatingURL with attachedURL (latest from chat session state)
    ▼
PageContextChipView (visible iff originatingURL != attachedURL)
```

### 8.2 Submit & attach

- Submit arrow tapped → `UnifiedToggleInputCoordinator.didSubmitPrompt(...)` (existing protocol on `AIChatInputBoxHandling`) → `AIChatContextualSheetCoordinator` routes to existing prompt path.
- Page chip tapped → coordinator triggers `pageContextHandler.triggerContextCollection()` → result pushes via `submitAIChatPageContext` user-script message (existing) → coordinator updates local `attachedURL` → chip recomputes visibility.

### 8.3 Frontend gating

- At `AIChatContextualWebViewController.makeContextualURL()`, when `featureFlagger.isFeatureOn(.unifiedToggleInput)` → append `nativeInput=1`.
- FE inspects the param at boot, skips its composer.
- `AIChatUserScript.setDisplayMode(.contextual)` continues unchanged.

## 9. Feature flag

- Reuse `unifiedToggleInput` (`iOS/Core/FeatureFlag.swift:305`).
- Single check site: presentation time of `AIChatContextualWebViewController`. Captured into a `Bool` and threaded into the URL builder + UTI installer.
- No sub-flag. If we later want a kill-switch specific to contextual, we can add a sub-feature behind the same parent.

## 10. Logging

`os.Logger(subsystem: "com.duckduckgo.mobile.ios", category: "ContextualUTI")` instruments:

- Flag state at presentation time.
- UTI installer path taken (FE composer vs native UTI).
- Page-chip visibility transitions (`hidden` ↔ `placeholder`) with the inputs that produced the change (`originatingURL`, `attachedURL`).
- Originating-tab URL changes received from `TabViewController`.
- Page-context attach actions (manual via chip / auto on page-change), with the URL.
- Submit events (prompt-only, since attach is independent now).

`privacy: .public` only on URLs that are already user-visible (the originating tab URL is, by definition, what the user is looking at). Prompts and page-context bodies are `.private`.

## 11. Testing

### 11.1 Unit tests (worth writing)

- **`UnifiedToggleInputPageContextChipViewModelTests`** — drive `(originatingURL, attachedURL, autoAttach)` permutations through the chip view-model and assert visibility + attach calls.
  - URL change to a new page → placeholder shown.
  - URL change back to attached page → hidden.
  - Auto-attach on, URL change → silent attach call, chip stays hidden.
  - Auto-attach off, URL change → placeholder shown, no attach call.
  - Manual tap → attach call, chip hides.
- **`AIChatURLParametersTests`** — adding the `nativeInput` param idempotently, surviving other params being present.

### 11.2 Integration tests (existing, must not regress)

- The existing `AIChatContextualSheet*` UI / unit tests must pass with the flag **off**.
- Add a smoke test (UI or snapshot) that the bottom of `AIChatContextualWebViewController` hosts a UTI when the flag is on.

### 11.3 Skipped (per project memory)

No unit tests for trivial pure logic (e.g. one-line equality predicates). Coverage focuses on the state machine and the URL builder.

## 12. Risk + open implementation questions

- **FE coordination:** the `nativeInput=1` query param is a contract. Confirm with the FE team that they'll honor it before merging the iOS side. Worst-case fallback: ship native UTI behind the flag *and* keep the FE composer until FE catches up — UI would have two composers, so this is only acceptable if the flag is off in production while we wait.
- **Page-change observation in `TabViewController`:** confirm `webViewUrlHasChanged()` fires *after* `WKWebView.url` updates and that the published URL matches what the user sees (not a transient `about:blank` during navigation). Tests here would help.
- **Sheet ↔ keyboard:** UTI in omnibar uses `keyboardLayoutGuide` for its floating-submit anchor; in the sheet host we suppress floating submit, but the UTI itself still needs to track keyboard avoidance inside the sheet. Verify that placing UTI as a child of `AIChatContextualWebViewController` with bottom-anchor + safe-area-relative-to-keyboard works without manual keyboard observers.
- **First-paint flicker:** at flag-on, the duck.ai page loads with `nativeInput=1` and FE never renders its composer. Until the native UTI's view is installed and laid out, there could be a sub-frame gap with no visible composer. Easy mitigation: install UTI synchronously in `viewDidLoad` of `AIChatContextualWebViewController` so it's already there when the page paints.

## 13. Rollout

- Implement behind the flag → confirm internally with `unifiedToggleInput` enabled.
- Coordinate with FE on the `nativeInput=1` honoring.
- No new flag rollout needed — piggyback on the existing UTI rollout cohort.
