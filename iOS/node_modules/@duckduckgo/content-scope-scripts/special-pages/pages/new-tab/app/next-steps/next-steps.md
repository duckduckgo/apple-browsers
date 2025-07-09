---
title: Next Steps Cards
---

## Setup

- Widget ID: `nextSteps`
- Add it to the `widgets` field on [initialSetup](../new-tab.md)
- Example:

```json
{
  "...": "...",
  "widgets": [
    {"id":  "nextSteps"},
    {"...":  "..."}
  ]
}
```

## Requests:
### `nextSteps_getData`
- {@link "NewTab Messages".NextStepsGetDataRequest}
- Used to fetch the initial data (during the first render)
- returns {@link "NewTab Messages".NextStepsData} - either `{content: null}` or `{content: Array<{id: string}>}`
- Note: Please use `null` to represent when there's nothing to show (instead of an empty array.)
- IDs: Please find the list of supported IDs here {@link "NewTab Messages".NextStepsCards}
- Example:

```json
{
  "content": [
    { "id": "bringStuff" },
    { "id": "defaultApp" }
  ]
}
```

or:

```json
{
  "content": null
}
```

### `nextSteps_getConfig`
- {@link "NewTab Messages".NextStepsGetConfigRequest}
- Used to fetch the initial config (during the first render)
- returns {@link "NewTab Messages".NextStepsConfig}

## Subscriptions:
### `nextSteps_onDataUpdate`
- {@link "NewTab Messages".NextStepsOnDataUpdateSubscription}.
- The messages available for the platform
- returns {@link "NewTab Messages".NextStepsData}
- as mentioned in the request, please use `null` to represent when there's nothing to show (instead of an empty array.)
### `nextSteps_onConfigUpdate`
- {@link "NewTab Messages".NextStepsOnConfigUpdateSubscription}.
- The widget-specific config, to toggle things like the expansion
- returns {@link "NewTab Messages".NextStepsConfig}

## Notifications:
### `nextSteps_action`
- {@link "NewTab Messages".NextStepsActionNotification}
- Sent when the user clicks the action button
- sends {@link "NewTab Messages".NextStepsActionNotify}
- example payload:
```json
{
  "id": "defaultApp"
}
```
### `nextSteps_dismiss`
- {@link "NewTab Messages".NextStepsDismissNotification}
- Sent when the user clicks the dismiss button
- sends {@link "NewTab Messages".NextStepsDismissNotify}
- example payload:
```json
{
  "id": "defaultApp"
}
```
### `nextSteps_setConfig`
- {@link "NewTab Messages".NextStepsSetConfigNotification}
- Sent when the user toggles the expansion of the next steps
- sends {@link "NewTab Messages".NextStepsConfig}
- example payload:
```json
{
  "expansion": "collapsed"
}
```
