---
title: Widget Config
---

## InitialSetup:

Data for widgets should be provided as part of the {@link "NewTab Messages".InitialSetupResponse `initialSetup`} response. The following keys should be added (also see the example below)
- `widgets`: {@link "NewTab Messages".Widgets}
- `widgetConfigs`: {@link "NewTab Messages".WidgetConfigs}

### `widgets`
This specifies which individual features will be present on the page. Some widgets may be initially hidden, waiting for data.

The following example will cause all 3 widgets to register in the page (potentially creating side effects). 

```json
[
    { "id": "rmf" },
    { "id": "favorites" },
    { "id": "privacyStats" }
]
```

The `id` field maps to a JavaScript file in the `entry-points` folder.
For example, `{ id: "rmf" }` will cause the module `entry-points/rmf.js` to register

### `widgetConfigs`
This provides the visibility (and other config in the future) of widgets that can be configured by the user. That's why 
it's normal for the `widgets` and `widgetConfigs` arrays to be different, for example:

```json
{
  "...": "...",
  "widgets": [
    { "id": "rmf" },
    { "id": "favorites" },
    { "id": "privacyStats" }
  ],
  "widgetConfigs": [
    { "id": "favorites", "visibility": "visible" },
    { "id": "privacyStats", "visibility": "hidden" }
  ]
}
```

## Subscriptions:
### `widgets_onConfigUpdated`
- {@link "NewTab Messages".WidgetsOnConfigUpdatedSubscription}
- returns {@link "NewTab Messages".WidgetConfigs}.


## Notifications:
### `widgets_setConfig`
- {@link "NewTab Messages".WidgetsOnConfigUpdatedSubscription}
- sends {@link "NewTab Messages".WidgetConfigs}

  If the user toggles the visibility of a section in the frontend, then the entire structure is sent to the
  native side.

## Examples:
The following examples show the data types in JSON format:
[messages/new-tab/examples/stats.js](../../messages/examples/widgets.js)
