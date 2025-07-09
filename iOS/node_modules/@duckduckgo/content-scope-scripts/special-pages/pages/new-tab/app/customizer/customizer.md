---
title: Customizer
---

## Drawer Feature Flag

- To enable the drawer feature for customization, change the {@link "NewTab Messages".NewTabPageSettings "Settings"} that are part of the `initialSetup` message
- It will default to the popover menu
- Example:


**Example InitialSetup response**

```json
{
  "...": "...",
  "widgets": [
    { "id": "rmf" },
    { "id": "nextSteps" },
    { "id": "favorites" },
    { "id": "privacyStats" }
  ],
  "widgetConfigs": [
    { "id": "favorites", "visibility": "visible" },
    { "id": "privacyStats", "visibility": "visible" }
  ],
  "settings": {
    "customizerDrawer": {
      "state": "enabled",
      "autoOpen": false
    }
  },
  "customizer": {
    "userImages": [],
    "userColor": null,
    "theme": "dark",
    "background": { "kind": "default" },
    "defaultStyles": {
      "lightBackgroundColor": "#E9EBEC",
      "darkBackgroundColor": "#27282A"
    }
  }
}
```

## Initial Data

- Add the key `customizer` to `initialSetup`
- The data takes the following form: {@link "NewTab Messages".CustomizerData}
- Example from `initialSetup`

```json
{
  "...": "...",
  "customizer": {
    "userImages": [],
    "userColor": null,
    "theme": "dark",
    "background": { "kind": "default" },
    "defaultStyles": {
      "lightBackgroundColor": "#E9EBEC",
      "darkBackgroundColor": "#27282A"
    }
  }
}
```

## Subscriptions

### `customizer_onBackgroundUpdate`
- {@link "NewTab Messages".CustomizerOnBackgroundUpdateSubscription}
- Sends {@link "NewTab Messages".BackgroundData} whenever needed.
- For example:
```json
{
  "background": { "kind": "color", "value": "color01" }
} 
```
```json
{
  "background": { "kind": "gradient", "value": "gradient01" }
} 
```
```json
{
  "background": { "kind": "hex", "value": "#cacaca" }
} 
```
```json
{
  "background": { "kind": "default" }
} 
```
```json
{
  "background": { 
     "kind": "userImage", 
     "value": { "id":  "abc", "src": "...", "thumb": "...", "colorScheme": "light" } 
  }
} 
```
      
### `customizer_onImagesUpdate`
- {@link "NewTab Messages".CustomizerOnImagesUpdateSubscription}.
- Sends {@link "NewTab Messages".UserImageData} whenever needed.
- For example, this would be pushed into the page following a successful upload
  - Note: In that situation, you'd send this followed by `customizer_onBackgroundUpdate` above
- For example:
```json
{
  "userImages": [{"id":  "abc", "src": "...", "thumb": "...", "colorScheme": "light" }]
} 
```
      
### `customizer_onColorUpdate`
- {@link "NewTab Messages".CustomizerOnColorUpdateSubscription}.
- Sends {@link "NewTab Messages".UserColorData} whenever needed.
- For example:
```json
{
  "userColor": { "kind": "hex", "value": "#cacaca" }
} 
```
  or:
```json
{
  "userColor": null
} 
```
      
### `customizer_onThemeUpdate`
- {@link "NewTab Messages".CustomizerOnThemeUpdateSubscription}.
- Sends {@link "NewTab Messages".ThemeData} whenever needed.
- For example:
```json
{
  "theme": "system"
} 
```
- Or, with optional `defaultStyles` example:
```json
{
  "theme": "system",
  "defaultStyles": {
    "lightBackgroundColor": "#E9EBEC",
    "darkBackgroundColor": "#27282A"
  }
}
```
  
### `customizer_autoOpen`
- {@link "NewTab Messages".CustomizerAutoOpenSubscription}.
- Send this into the page to trigger the customizer to be opened.

## Notifications

### `customizer_setBackground`
- {@link "NewTab Messages".CustomizerSetBackgroundNotification}.
- Sends {@link "NewTab Messages".CustomizerSetBackgroundNotify} whenever needed.
- For example:
```json
{
  "background": { "kind": "color", "value": "color01" }
} 
```

### `customizer_setTheme`
- {@link "NewTab Messages".CustomizerSetThemeNotification}.
- Sends {@link "NewTab Messages".CustomizerSetBackgroundNotify} whenever needed.
- For example:
```json
{
  "theme": "light"
} 
```

### `customizer_upload`
- {@link "NewTab Messages".CustomizerUploadNotification}.
- Sent to trigger a file upload
  
### `customizer_deleteImage`
- {@link "NewTab Messages".CustomizerDeleteImageNotification}.
- Sends {@link "NewTab Messages".CustomizerDeleteImageNotify} whenever needed.
- For example:
```json
{
  "id": "abc"
} 
```
  
### `customizer_contextMenu`
- {@link "NewTab Messages".CustomizerContextMenuNotification}.
- Sends {@link "NewTab Messages".UserImageContextMenu} 
- Note: only sent for right-clicks on user images in the selection screen.
- For example:
```json
{
  "target": "userImage",
  "id": "01"
} 
```
