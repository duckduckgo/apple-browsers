---
title: Favorites API
---

# Public API for the Favorites Widget.

## Drag + Drop

When dragging - the follow data is available:

 - `"text/plain": "<favorite url>"`
 - `"application/vnd.duckduckgo.bookmark-by-id": "<favorite id>"`
 - See this link for the actual value used in code: {@link "New Tab Constants".DDG_MIME_TYPE}

## Favicons

There are three representations of a favicon: image source, letters, or fallback icon

- if the favicon image source is absent, or it fails to load (404), we'll then try to use 'letters'
- if the `etldPlusOne` field is `null` though, we won't use any letters, and we'll load a default globe icon instead 

## Requests:

### `favorites_getData`
- {@link "NewTab Messages".FavoritesGetDataRequest}
- Used to fetch the initial data (during the first render)
- returns {@link "NewTab Messages".FavoritesData}

### `favorites_getConfig`
- {@link "NewTab Messages".FavoritesGetDataRequest}
- Used to fetch the initial data (during the first render)
- returns {@link "NewTab Messages".FavoritesConfig}

## Subscriptions:

### `favorites_onDataUpdate`
- {@link "NewTab Messages".FavoritesOnDataUpdateSubscription}.
- The tracker/company data used in the feed.
- returns {@link "NewTab Messages".FavoritesData}

### `favorites_onConfigUpdate`
- {@link "NewTab Messages".FavoritesOnConfigUpdateSubscription}.
- The widget config
- returns {@link "NewTab Messages".FavoritesConfig}

### `favorites_onRefresh`
- {@link "NewTab Messages".FavoritesOnRefreshSubscription}.
- Used to indicate potential updates, like when a favicon DB is ready
- returns {@link "NewTab Messages".FavoritesRefresh}


## Notifications:

### `favorites_setConfig`
- {@link "NewTab Messages".FavoritesSetConfigNotification}
- Sent when the user toggles the expansion of the favorites
- Sends {@link "NewTab Messages".FavoritesConfig}
- Example payload:
```json
{
  "expansion": "collapsed"
}
```

### `favorites_move`
- {@link "NewTab Messages".FavoritesMoveNotification}
- Sends {@link "NewTab Messages".FavoritesMoveAction}
- When you receive this message, apply the following
- Search your collection to find the object with the given `id`.
- Remove that object from its current position.
- Insert it into the new position specified by `targetIndex`.
- Example payload:
```json
{
 "id": "abc",
 "targetIndex": 1
}
```
      
### `favorites_openContextMenu`
- {@link "NewTab Messages".FavoritesOpenContextMenuNotification}
- Sends {@link "NewTab Messages".FavoritesOpenContextMenuAction}
- When you receive this message, show the context menu for the entity
- Example payload:
```json
{
  "id": "abc"
}
```

### `favorites_open`
- {@link "NewTab Messages".FavoritesOpenNotification}
- Sends {@link "NewTab Messages".FavoritesOpenNotification}
- When you receive this message, open the favorite in the given target
- Example payload:
```json
{
   "id": "abc",
   "target": "same-tab"
}
```
