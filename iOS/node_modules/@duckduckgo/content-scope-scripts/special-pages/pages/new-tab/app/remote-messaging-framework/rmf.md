---
title: Remote Messaging Framework
---

## Requests:
### `rmf_getData`
- {@link "NewTab Messages".RmfGetDataRequest}
- Used to fetch the initial data (during the first render)
- returns {@link "NewTab Messages".RMFData}

## Subscriptions:
### `rmf_onDataUpdate`
- {@link "NewTab Messages".RmfOnDataUpdateSubscription}.
- The messages available for the platform
- returns {@link "NewTab Messages".RMFData}

## Notifications:
### `rmf_primaryAction`
- {@link "NewTab Messages".RmfPrimaryActionNotification}
- Sent when the user clicks the primaryAction button
- sends {@link "NewTab Messages".RMFPrimaryAction}
- example payload:
```json
{
  "id": "windows_privacy_pro_survey_2"
}
```
### `rmf_secondaryAction`
- {@link "NewTab Messages".RmfSecondaryActionNotification}
- Sent when the user clicks the secondaryAction button
- sends {@link "NewTab Messages".RMFSecondaryAction}
- example payload:
```json
{
  "id": "windows_privacy_pro_survey_2"
}
```
### `rmf_dismiss`
- {@link "NewTab Messages".RmfDismissNotification}
- Sent when the user clicks the dismiss button
- sends {@link "NewTab Messages".RMFDismissAction}
- example payload:
```json
{
  "id": "windows_privacy_pro_survey_2"
}
```

## Examples:

The following examples show the data types in JSON format:
[messages/new-tab/examples/stats.js](../../messages/examples/rmf.js)
