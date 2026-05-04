# Per-Tab Unified Input State (iOS)

**Status:** design — accepted by user, awaiting implementation plan
**Date:** 2026-05-04
**Branch:** `bunn/input/persist-cl`

## Problem

The iOS unified input field (search + Duck.ai) is a single `UnifiedToggleInputCoordinator` instance shared across tabs. On tab switch, `bindToTab(_:)` calls `resetSessionState()`, wiping in-progress text, attachments, tool selection, and the toggle mode. The user expects each tab to remember what it was holding so switching back restores the input as the user left it.

## Goals

- Each tab remembers its own input state — text, toggle position, attachments, model, reasoning effort, tool selection — across tab switches.
- New tabs seed defaults from the most recently used values (last-write-wins across tabs).
- One unified home for all per-tab input state, behind a protocol.
- No regression for the existing `Tab.preferredTextEntryMode` (currently NSCoding-persisted per tab).

## Non-goals

- Persistence across app cold launches for fields other than the toggle. State is in-memory; cold launch resets text, attachments, model selection per tab to current global defaults (toggle continues to survive cold launch via existing `Tab.preferredTextEntryMode` encoding).
- No disk format, no migration, no encryption work for attachments.
- No change to the global preference homes (`ToggleModeStorage`, `AIChatPreferencesPersisting`) — they remain canonical for last-used values.

## User decisions captured

1. **Persistence durability:** in-memory across tab switches (chosen: A).
2. **Per-tab fields:** text, toggle, attachments, model id, reasoning effort, tool selection. New tabs seed from last-used choice across all tabs.
3. **One unified home for per-tab state**, protocol-based.
4. **`Tab.preferredTextEntryMode`:** keep NSCoding for the toggle only; other fields stay in-memory.
5. **Lifecycle:** eager — per-tab state is created on tab birth from current global defaults.

## Architecture

### Components

```
┌──────────────────────────────────┐
│  UnifiedInputStateStoring (proto) │
│  - state(for: TabUID) -> TabInputState     │
│  - update(_:for: TabUID)                   │
│  - remove(for: TabUID)                     │
│  - lastUsed: LastUsedInputDefaults         │
└──────────────────┬───────────────┘
                   │
        ┌──────────┴──────────────┐
        │                         │
┌───────▼────────────────┐  ┌─────▼──────────────────────┐
│  UnifiedInputStateStore │  │ MockUnifiedInputStateStore │
│  (production)           │  │  (tests)                   │
└─────────────────────────┘  └────────────────────────────┘
```

- **`TabInputState`** — value struct, the unit of per-tab state.
- **`UnifiedInputStateStoring`** — protocol the coordinator depends on; injected at coordinator construction time.
- **`UnifiedInputStateStore`** — concrete store. Owns `[TabUID: TabInputState]`, observes `TabsModel` for tab adds/removes/burns, exposes `lastUsed` reading through to `ToggleModeStorage` and `AIChatPreferencesPersisting`.
- The coordinator becomes a stateless-per-tab consumer: hydrate from store on bind, flush back on unbind, propagate user mutations into the store.

### `TabInputState`

```swift
struct TabInputState: Equatable {
    var text: String
    var toggleMode: TextEntryMode
    var attachments: [AIChatImageAttachment]
    var selectedModelID: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
}
```

(The existing `UTIToolsController` exposes a single `selectedTool: AIChatRAGTool?` — only `.webSearch` is implemented today. The struct mirrors that single-value shape.)

A small `LastUsedInputDefaults` value type holds the seedable defaults (toggle, model id, reasoning, tool set — not text or attachments). The store materializes it on read by reading through to existing canonical homes where one exists:

- `toggleMode`: `ToggleModeStorage` (canonical, persisted)
- `selectedModelID`: `AIChatPreferencesPersisting.selectedModelId` (canonical, persisted)
- `selectedReasoningMode`: `AIChatPreferencesPersisting.selectedReasoningMode` (canonical, persisted)
- `selectedTool`: **in-memory only on the store**. Tools have no canonical persisted home today; see Risks.

`TabUID` is a typealias for `String` (matches `Tab.uid`).

## Data flow

### Tab creation (eager)
`TabsModel.add(tab:)` → store inserts a fresh `TabInputState` for `tab.uid`, populated from `lastUsed`. `toggleMode` is sourced from `tab.preferredTextEntryMode` (which is itself seeded from settings on creation, or restored from NSCoding on cold launch), so cold-launch state for the toggle survives. Other fields seed from `lastUsed`.

### Tab activation (bind)
`refreshUnifiedToggleInput(for: tab)` → coordinator calls `store.state(for: tab.uid)` → applies it:
- text → `SwitchBarHandler.updateCurrentText`
- toggle → `SwitchBarHandler.setToggleState`
- attachments → `UnifiedToggleInputView.setAttachments`
- model + reasoning → `UTIModelStore` / `AIChatPreferencesPersisting` (live preferences)
- tools → `UTIToolsController`

### Tab deactivation / re-bind
Before binding to a new tab, coordinator snapshots its current state and calls `store.update(_:for: previousUID)`. This replaces today's `resetSessionState()` (which discards state).

### User mutation (active tab)
Existing change publishers fire (`textChangeSubject`, mode change, attachments change subject, model selection, tool selection). Coordinator updates its live state and pushes through to the store keyed by the active tab uid.

Because toggle/model/reasoning all already have global persisted homes (`ToggleModeStorage`, `AIChatPreferencesPersisting`), and those globals are read by the model store / switch handler / `Tab.preferredTextEntryMode` initialization, the global preferences are simultaneously kept in sync with the active tab's values. This automatically gives "last used = next new tab" without an extra mechanism: when tab N becomes active, its values are written through to the globals; when a new tab is created later, eager seeding reads the same globals.

### Tab removal / burn
Store evicts the entry on `TabsModel`-observed removal. Fire-tab burn evicts every fire-tab entry. No dangling state.

### Submission
On successful submit, `text` and `attachments` clear in the store entry (matches existing behavior). `toggleMode`, `selectedModelID`, `selectedReasoningMode`, `selectedTools` are preserved in the entry for the next prompt in the same tab.

## `Tab.preferredTextEntryMode` interaction

- Stays NSCoding-encoded on `Tab` — no schema change.
- Becomes the persisted slice of `TabInputState.toggleMode`. When the toggle flips in tab *N*, the store writes through to `tab.preferredTextEntryMode` so cold launch can re-seed.
- Other `TabInputState` fields are pure in-memory; cold launch resets them to current `lastUsed`.

## Coordinator changes

| Existing | After |
|---|---|
| `bindToTab` calls `resetSessionState()` on different identifier | `bindToTab` flushes the outgoing tab's state to the store, then calls `applyState(store.state(for: tab.uid))` |
| State changes are local to coordinator | State changes also call `store.update(_:for: currentTabUID)` |
| No snapshot on unbind | New `flushCurrentStateToStore(for: previousUID)` runs before re-bind / unbind |

`resetSessionState()` is narrowed, not removed: it stops clearing per-tab fields (`text`, `attachments`, tools) and keeps clearing chat-binding-only state (`isNewChatPending`, `aiChatStatus`, `aiChatInputBoxVisibility`, `hasSubmittedPrompt`, `attachmentUsage`). The per-tab fields are replaced by the hydrate step.

## Files

**New** (under `iOS/DuckDuckGo/UnifiedToggleInput/`):
- `TabInputState.swift` — value struct.
- `UnifiedInputStateStoring.swift` — protocol and `LastUsedInputDefaults`.
- `UnifiedInputStateStore.swift` — production store, lifecycle observer.

**Modified:**
- `UnifiedToggleInputCoordinator.swift` — replace `resetSessionState` with hydrate/flush; tap mutation publishers.
- `MainViewController+UnifiedToggleInput.swift` — construct + inject the store; pass the active tab uid into refresh path.
- `TabsModel.swift` (or its observer plumbing) — ensure store can subscribe to add/remove/burn.

**Unchanged:** `Tab.swift` (other than continued use of `preferredTextEntryMode`).

## Testing

- `UnifiedInputStateStoreTests`
  - eager seeding on tab add uses `lastUsed`
  - mutation updates `lastUsed` for seedable fields
  - `remove(for:)` on tab removal
  - burn evicts every fire-tab entry
  - read-through to `Tab.preferredTextEntryMode` for the toggle slice
- `UnifiedToggleInputCoordinatorTests` (existing target)
  - hydrate on bind: applies all six fields
  - flush on unbind: store sees the latest snapshot
  - submission clears text + attachments in the store, leaves the rest
  - test fake conforms to `UnifiedInputStateStoring`
- `Tab` round-trip test for `preferredTextEntryMode` — unchanged.

## Risks / open questions

- **Tools have no global `lastUsed` home today.** The store invents one in-memory. If this is later wanted across cold launches, it needs persistent backing — out of scope for this design.
- **Memory growth with many tabs holding attachments.** Attachments are decoded `UIImage`s. With dozens of tabs each holding several images this could matter. Eviction on tab removal mitigates the steady state. If pathological, a follow-up could cap attachment count or move to a thumbnail-on-eviction scheme.
- **The store is `@MainActor`-bound** (matches the coordinator). Tab lifecycle observers must hop to main if they fire off-main.
