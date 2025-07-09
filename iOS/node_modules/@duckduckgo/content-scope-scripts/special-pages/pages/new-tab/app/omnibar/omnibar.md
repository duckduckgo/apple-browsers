---
title: Omnibar Widget
---

## Setup

- Widget ID: `"omnibar"`
- Add it to the `widgets` + `widgetConfigs` fields on [initialSetup](../new-tab.md)
- Example:

```json
{
  "...": "...",
  "widgets": [
    {"...":  "..."},
    {"id": "omnibar"}
  ],
  "widgetConfigs": [
    {"...":  "..."},
    {"id": "omnibar", "visibility": "visible" }
  ]
}
```

## Requests:

### `omnibar_getConfig` 
- {@link "NewTab Messages".OmnibarGetConfigRequest}
- Used to fetch the initial config data (during the first render)
- returns {@link "NewTab Messages".OmnibarConfig}
```json
{
   "mode": "search"
}
```

### `omnibar_getSuggestions` 
- {@link "NewTab Messages".OmnibarGetSuggestionsRequest}
- Used to fetch search suggestions based on user input
- requires `term` parameter (the search term to get suggestions for)
- returns {@link "NewTab Messages".SuggestionsData}
```json
{
   "suggestions": {
      "topHits": [
         {
            "kind": "bookmark",
            "title": "Example Site",
            "url": "https://example.com",
            "isFavorite": true,
            "score": 0.95
         }
      ],
      "duckduckgoSuggestions": [
         {
            "kind": "phrase",
            "phrase": "example search term"
         }
      ],
      "localSuggestions": [
         {
            "kind": "historyEntry",
            "title": "Previous Visit",
            "url": "https://previous.com",
            "score": 0.8
         }
      ]
   }
}
```

## Subscriptions:

### `omnibar_onConfigUpdate` 
- {@link "NewTab Messages".OmnibarOnConfigUpdateSubscription}
- The omnibar widget configuration updates
- returns {@link "NewTab Messages".OmnibarConfig}

## Notifications:

### `omnibar_setConfig` 
- {@link "NewTab Messages".OmnibarSetConfigNotification}
- Sent when the user changes the omnibar mode (search vs AI)
- sends {@link "NewTab Messages".OmnibarConfig}
- example payload:
```json
{
   "mode": "ai"
}
```

### `omnibar_submitSearch` 
- {@link "NewTab Messages".OmnibarSubmitSearchNotification}
- Sent when the user submits a search query
- requires `term` (the search term) and `target` (where to open the search)
- example payload:
```json
{
   "term": "duckduckgo privacy",
   "target": "same-tab"
}
```

### `omnibar_submitChat` 
- {@link "NewTab Messages".OmnibarSubmitChatNotification}
- Sent when the user submits a chat message to Duck.ai
- requires `chat` (the chat message) and `target` (where to open the chat)
- example payload:
```json
{
   "chat": "How do I enable privacy protection?",
   "target": "new-tab"
}
```

### `omnibar_openSuggestion` 
- {@link "NewTab Messages".OmnibarOpenSuggestionNotification}
- Sent when the user selects a suggestion from the dropdown
- requires `suggestion` (the selected suggestion) and `target` (where to open it)
- example payload:
```json
{
   "suggestion": {
      "kind": "bookmark",
      "title": "DuckDuckGo",
      "url": "https://duckduckgo.com",
      "isFavorite": true,
      "score": 1.0
   },
   "target": "same-tab"
}
```

## Suggestion Types

The omnibar supports various types of suggestions:

- **bookmark**: Saved bookmarks with title, URL, favorite status, and relevance score
- **openTab**: Currently open browser tabs with title, tab ID, and relevance score  
- **phrase**: Search phrase suggestions from DuckDuckGo
- **website**: Direct website URL suggestions
- **historyEntry**: Previously visited pages from browser history with title, URL, and relevance score
- **internalPage**: Internal browser pages (settings, etc.) with title, URL, and relevance score

## Open Targets

All actions that open content support these target options:
- `"same-tab"`: Replace current tab content
- `"new-tab"`: Open in a new tab
- `"new-window"`: Open in a new browser window