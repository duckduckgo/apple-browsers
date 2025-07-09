---
title: Freemium PIR Banner
---

## Requests:
- {@link "NewTab Messages".FreemiumPIRBannerGetDataRequest `freemiumPIRBanner_getData`}
    - Used to fetch the initial data (during the first render)
    - returns {@link "NewTab Messages".FreemiumPIRBannerData}

## Subscriptions:
- {@link "NewTab Messages".FreemiumPIRBannerOnDataUpdateSubscription `freemiumPIRBanner_onDataUpdate`}.
    - The messages available for the platform
    - returns {@link "NewTab Messages".FreemiumPIRBannerData}

## Notifications:
- {@link "NewTab Messages".FreemiumPIRBannerActionNotification `freemiumPIRBanner_action`}
    - Sent when the user clicks the action button
    - sends {@link "NewTab Messages".FreemiumPIRBannerAction}
    - example payload:
      ```json
      {
        "id": "onboarding"
      }
      ```
- {@link "NewTab Messages".FreemiumPIRBannerDismissNotification `freemiumPIRBanner_dismiss`}
    - Sent when the user clicks the dismiss button
    - sends {@link "NewTab Messages".FreemiumPIRBannerDismissAction}
    - example payload:
      ```json
      {
        "id": "scan_results"
      }
      ```

## Examples:

The following examples show the data types in JSON format:
[messages/new-tab/examples/stats.js](../../messages/examples/freemiumPIRBanner.js)
