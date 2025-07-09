---
title: History View
---

# History view

## Requests

### `initialSetup`
{@link "History Messages".InitialSetupRequest}

Configure initial history system settings.

**Types:**
- Response: {@link "History Messages".InitialSetupResponse}

```json
{
  "locale": "en",
  "env": "production",
  "platform": {
    "name": "macos"
  }
}
```

With {@link "History Messages".DefaultStyles} overrides 

```json
{
  "locale": "en",
  "env": "production",
  "platform": {
    "name": "macos"
  },
  "customizer": {
    "defaultStyles": {
      "lightBackgroundColor": "#E9EBEC",
      "darkBackgroundColor": "#27282A"
    }
  }
}
```

### `getRanges`
{@link "History Messages".GetRangesRequest}

Retrieves available time ranges for history filtering.

**Types:**
- Response: {@link "History Messages".GetRangesResponse}

```json
{
  "ranges": [
    {
      "id": "today",
      "count": 13
    },
    {
      "id": "yesterday",
      "count": 10
    },
    {
      "id": "monday",
      "count": 2
    },
    {
      "id": "older",
      "count": 120
    }
  ]
}
```


### `query`
{@link "History Messages".QueryRequest}

Queries history items with filtering and pagination.

**Types:**
- Parameters: {@link "History Messages".HistoryQuery}
- Response: {@link "History Messages".HistoryQueryResponse}

params for a query: (note: can be an empty string!)

```json
{
  "query": {
    "term": "example.com"
  },
  "offset": 0,
  "limit": 50,
  "source": "initial"
}
```

params for a range, note: the values here will match what you returned from `getRanges`

```json
{
  "query": {
    "range": "today"
  },
  "offset": 0,
  "limit": 50,
  "source": "initial"
}
```

Response, note: always return the same query I sent: 

```json
{
  "info": {
    "finished": false,
    "query": {
      "term": "example.com"
    }
  },
  "value": [
    {
      "id": "12345",
      "dateRelativeDay": "Today - Wednesday 15 January 2025",
      "dateShort": "15 Jan 2025",
      "dateTimeOfDay": "11:01",
      "domain": "example.com",
      "etldPlusOne": "example.com",
      "title": "Example Website",
      "url": "https://example.com/page",
      "favicon": {
        "src": "...",
        "maxAvailableSize": 64
      }
    }
  ]
}
```

### `deleteRange`
- Sent to delete a range as displayed in the sidebar.
- Parameters: {@link "History Messages".DeleteRangeParams}
- If the user confirms, respond with `{ action: 'delete' }`
- otherwise `{ action: 'none' }`
  - Response: {@link "History Messages".DeleteRangeResponse}

**params**
```json
{
  "range": "today" 
}
```

**response**
```json
{
  "action": "delete" 
}
```

### `deleteDomain`
- Sent to delete a domain - which might be the etld+1 or domain.
- Parameters: {@link "History Messages".DeleteDomainParams}
- If the user confirms, respond with `{ action: 'delete' }`
- otherwise `{ action: 'none' }`
  - Response: {@link "History Messages".DeleteDomainResponse}

**params**
```json
{
  "domain": "youtube.com" 
}
```

**response**
```json
{
  "action": "delete" 
}
```

### `deleteTerm`
- Sent to delete a search term
- Parameters: {@link "History Messages".DeleteTermParams}
- If the user confirms, respond with `{ action: 'delete' }`
- otherwise `{ action: 'none' }`
  - Response: {@link "History Messages".DeleteTermResponse}

**params**
```json
{
  "term": "youtube" 
}
```

**response**
```json
{
  "action": "delete" 
}
```

**response, if deleted**
```json
{
  "action": "delete" 
}
```

**response, otherwise**
```json
{
  "action": "none" 
}
```

### `entries_menu`
{@link "History Messages".EntriesMenuRequest}

Sent when a right-click is issued on a section title (or when the three-dots button is clicked)  

**Types:**
- Parameters: {@link "History Messages".EntriesMenuParams}
- Response: {@link "History Messages".EntriesMenuResponse}

**params**
```json
{
  "ids": ["abc", "def"]
}
```

**response, if deleted**
```json
{
  "action": "delete" 
}
```

**response, to trigger a domain search**
```json
{
  "action": "domain-search" 
}
```

**response, otherwise**
```json
{
  "action": "none" 
}
```

### `entries_delete`
{@link "History Messages".EntriesDeleteRequest}
{@link "History Messages".EntriesDeleteRequest}

Sent when the delete key is pressed on an item, or a group of items

**Types:**
- Parameters: {@link "History Messages".EntriesDeleteParams}
- Response: {@link "History Messages".EntriesDeleteResponse}

Note: if a single `id` is sent, **no modal/confirmation should be shown** - but you must
still reply with an {@link "History Messages".ActionResponse} when the action was completed.

If multiple `id`s are sent, then present a modal window for confirmation, eventually 
responding to the message with {@link "History Messages".ActionResponse}

## Notifications

### `open`
- {@link "History Messages".OpenNotification}
- Sent when a user clicks a link, sends {@link "History Messages".OpenNotification}
- Target is one of {@link "History Messages".OpenTarget}

example payload
```json
{ 
  "url": "https://example.com/path", 
  "target": "same-tab" 
}
```
```json
{ 
  "url": "https://example.com/path", 
  "target": "new-tab" 
}
```

### `reportInitException`
{@link "History Messages".ReportInitExceptionNotification}

Reports initialization errors in the history system.

```json
{
  "message": "Failed to initialize history database"
}
```

### `reportPageException`
{@link "History Messages".ReportPageExceptionNotification}

Reports errors during page history operations.

```json
{
  "message": "Failed to load page history"
}
```