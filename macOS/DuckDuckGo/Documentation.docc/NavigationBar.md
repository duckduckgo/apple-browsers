# Navigation & Address Bar

URL input handling, search suggestions, privacy indicators, and navigation controls.

## Overview

The navigation bar is the primary interface for user-initiated navigation in the DuckDuckGo browser. The `AddressBarTextField` is the core component, and its central problem is genuinely non-obvious: a single string the user types can be a URL, a search query, or a chosen suggestion, and the field has to decide which without a submit-time round trip. URL/search disambiguation, suggestion display, and HTTPS upgrading all hang off that decision.

The architecture integrates with the browser's suggestion system, drawing real-time suggestions from bookmarks, history, open tabs, and search phrases.

## Architecture

```
NavigationBarViewController
├── AddressBarViewController
│   ├── AddressBarTextField (URL Input)
│   ├── PrivacyIconViewModel (Privacy state)
│   └── Address Bar Buttons (refresh, settings, etc.)
└── SuggestionViewController (Dropdown)
    └── SuggestionContainerViewModel
```

## Key Components

### Navigation Bar Controllers

- ``NavigationBarViewController`` — main navigation bar container; coordinates child view controllers and manages layout and appearance.
- ``AddressBarViewController`` — address bar section controller; integrates the privacy icon and manages the surrounding buttons.

### Address Bar Input

- ``AddressBarTextField`` — core URL/search input field; handles suggestion integration, value parsing, validation, and navigation logic.

### Suggestions

- ``SuggestionViewController`` — suggestion dropdown UI; handles keyboard navigation and selection.
- ``SuggestionContainerViewModel`` — suggestion data source; filtering and ranking against bookmarks, history, and open tabs.

## URL vs. Search Detection

The field models its content as a three-state ``AddressBarTextField/Value`` (`.text`, `.url`, `.suggestion`) rather than a plain string because downstream behavior depends on *which* it is: the navigation target, whether inline autocomplete is offered, and what the privacy icon reflects all differ between a half-typed query and a resolved URL. Parsing runs through `URL(trimmedAddressBarString:)`, which carries the URL-vs-search heuristics.

## Privacy Indicators

The privacy icon is driven by ``PrivacyIconViewModel``, which derives its state from the current tab's privacy info (connection security, tracker protection status, and any per-site exceptions). The address bar binds to it so the icon tracks the tab's privacy state as navigation proceeds — the indicator reflects the live connection, not the typed string.

## Design Notes

### URL Validation

URL validation uses `URL(trimmedAddressBarString:useUnifiedLogic:)`. The unified-logic path is feature-flagged so the newer prediction behavior can be rolled out independently. IDN domains are punycode-encoded when the URL is constructed for validation, while a decoded Unicode form is kept for display when the field is being edited — so the host is validated in its ASCII-compatible form but still shown readably.

### Autocomplete Behavior

Inline autocompletion is deliberately conservative: it appears only when the completion is unambiguous, preserves the user's capitalization, and pre-selects the appended suffix so a single keystroke deletes it. The intent is to never commit the user to a destination they didn't type.

### HTTPS Upgrading

URLs are upgraded to HTTPS as part of navigation handling, so the upgrade applies regardless of how navigation was initiated (typed, suggestion, paste-and-go).

## Topics

### Controllers

- ``NavigationBarViewController``
- ``AddressBarViewController``
- ``SuggestionViewController``

### Address Bar

- ``AddressBarTextField``
- ``PrivacyIconViewModel``

### Suggestions

- ``SuggestionContainerViewModel``

### Related

- <doc:TabManagement>
