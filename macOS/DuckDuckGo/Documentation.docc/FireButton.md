# Fire Button & Data Clearing

Selective and complete data clearing with fireproofing support for trusted sites.

## Overview

The Fire Button is DuckDuckGo's signature privacy feature that allows users to quickly clear browsing data. It provides granular control over what data to clear (tabs, history, cookies, site data) while respecting "fireproofed" sites that users want to keep logged into. The implementation spans multiple components that coordinate to clear data from various subsystems including WebKit, Core Data, and the filesystem.

The architecture supports multiple clearing scopes: individual tabs, entire windows, or all browsing data. The Fire Dialog (feature-flagged) provides a modern UI for selecting what to clear, while the underlying `Fire` class orchestrates the actual data clearing across all relevant managers.

## Architecture

```
FireViewController (UI)
    ↓
FireCoordinator (Coordination)
    ↓
FireViewModel (State)
    ↓
Fire (Data Clearing Engine)
    ├── WebCacheManager (WebKit data)
    ├── HistoryCoordinator (History/visits)
    ├── PermissionManager (Site permissions)
    ├── SavedZoomLevelsCoordinating (Zoom levels)
    ├── DownloadListCoordinator (Downloads list)
    ├── FaviconManagement (Favicons)
    ├── AutoconsentManagement (Cookie consent state)
    ├── AutofillVaultFactory (Autofill data)
    └── AIChatHistoryCleaning (AI Chat history)
```

### Data Types Cleared

- **Tabs & Windows**: Close tabs/windows
- **History**: Browsing history entries and visits
- **Cookies & Site Data**: Cookies, local storage, cache
- **Permissions**: Location, camera, microphone permissions
- **Downloads**: Download history (not files)
- **Favicons**: Site icons
- **Zoom Levels**: Per-site zoom preferences
- **Autoconsent State**: Cookie banner preferences
- **Chat History**: AI Chat conversations
- **Visited Links**: WebKit visited links tracking

## Key Components

### UI Components

- ``FireViewController`` — presents the fire animation (a Lottie overlay) while burning is in progress; driven by a ``FireViewModel``. The fire-button action, popover, and dialog presentation live in ``FireCoordinator``.
- ``FirePopoverViewController`` — legacy fire popover UI with options for what to clear.
- ``FireDialogViewModel`` — new Fire Dialog state management; carries the clearing-options enum (current tab, current window, all data) and the toggle states for individual data categories.

### Coordination

- ``FireCoordinator`` — coordinates the Fire Dialog UI and the clearing actions; translates user selections into ``Fire`` engine calls.

### Core Engine

- ``Fire`` — main data clearing engine; orchestrates clearing across all managers, handles fireproofing exceptions, and uses dispatch groups to coordinate async operations.

### Supporting Models

- ``FireproofDomains`` — manages fireproofed (trusted) domains that are excluded from Fire clearing.

## Common Tasks

### Clearing Data

The Fire system supports multiple clearing scopes:
- Clear all data across all windows
- Clear current tab
- Clear current window
- Clear specific history visits by date range

Use ``Fire/BurningEntity`` to define the scope — its cases are `.tab(tabViewModel:selectedDomains:parentTabCollectionViewModel:close:)`, `.window(tabCollectionViewModel:selectedDomains:close:)`, `.allWindows(mainWindowControllers:selectedDomains:customURLToOpen:close:)`, and `.none(selectedDomains:)` — then call `burnEntity` on ``Fire`` with options for what to include (history, cookies, chat history).

### Fireproofing

Fireproof domains are excluded from Fire clearing. ``FireproofDomains`` exposes the add, remove, and lookup operations used by settings and the Fire engine to manage these trusted sites.

### Showing Fire Dialog

Access the Fire UI through ``FireCoordinator`` — it owns the presentation of the dialog from the main window.

Refer to ``Fire``, ``FireCoordinator``, and ``FireproofDomains`` for implementation details.

## Patterns & Best Practices

### Burning Entities

The ``Fire/BurningEntity`` enum defines the scope of clearing — `.tab`, `.window`, `.allWindows`, and `.none`. Each case carries the relevant view models and a `selectedDomains` set; the closing variants also carry a `close` flag controlling whether the UI is dismissed or only the underlying state is cleared. Use `.allWindows` with an empty `selectedDomains` set for a full Fire, or `.none` to clear data without closing any UI.

### Domain Handling

Always convert domains to eTLD+1 form before passing them to the Fire engine — this ensures subdomain variants are handled consistently across cookies, storage, and history.

### Fireproofing

Fireproofed domains are completely excluded from clearing. The Fire engine automatically filters them out when determining domains to burn.

### Fire Animation

Fire animation is controlled by user preferences via ``VisualizeFireSettingsDecider``.

## Fire Dialog (Feature-Flagged)

The new Fire Dialog provides enhanced UX with visual options (clear current tab, window, or all data), granular toggles for what gets cleared, persistent settings, and time range selection.

See ``FireDialogViewModel`` for the clearing options enum and result structure.

## Topics

### Core

- ``Fire``
- ``FireCoordinator``
- ``FireproofDomains``

### UI

- ``FireViewController``
- ``FirePopoverViewController``
- ``FireDialogViewModel``

### Related

- <doc:TabManagement>

