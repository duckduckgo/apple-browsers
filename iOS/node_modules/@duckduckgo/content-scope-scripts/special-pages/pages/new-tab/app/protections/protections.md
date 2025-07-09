---
title: Protections Report
---

## Setup

- Widget ID: `"protections"`
- Add it to the `widgets` + `widgetConfigs` fields on [initialSetup](../new-tab.md)
- Example:

```json
{
  "...": "...",
  "widgets": [
    {"...":  "..."},
    {"id": "protections"}
  ],
  "widgetConfigs": [
    {"...":  "..."},
    {"id": "protections", "visibility": "visible" }
  ]
}
```

## Requests:
### `protections_getData` 
- {@link "NewTab Messages".ProtectionsGetDataRequest}
- Used to fetch the initial data (during the first render)
- returns {@link "NewTab Messages".ProtectionsData}
```json
{
   "totalCount": 84
}
```

### `protections_getConfig` 
- {@link "NewTab Messages".ProtectionsGetDataRequest}
- Used to fetch the initial config data (eg: expanded vs collapsed)
- returns {@link "NewTab Messages".ProtectionsConfig}
```json
{
   "expansion": "collapsed",
   "feed": "privacy-stats",
   "showBurnAnimation": true
}
```

## Subscriptions:
### `protections_onDataUpdate` 
- {@link "NewTab Messages".ProtectionsOnDataUpdateSubscription}.
- The tracker/company data used in the feed.
- returns {@link "NewTab Messages".ProtectionsData}
### `protections_onConfigUpdate` 
- {@link "NewTab Messages".ProtectionsOnConfigUpdateSubscription}.
- The widget config
- returns {@link "NewTab Messages".ProtectionsConfig}

## Notifications:
### `protections_setConfig` 
- {@link "NewTab Messages".ProtectionsSetConfigNotification}
- Sent when the user toggles the expansion of the stats
- sends {@link "NewTab Messages".ProtectionsConfig}
- example payload:
```json
{
   "expansion": "collapsed",
   "feed": "privacy-stats",
   "showBurnAnimation": true
}
```
