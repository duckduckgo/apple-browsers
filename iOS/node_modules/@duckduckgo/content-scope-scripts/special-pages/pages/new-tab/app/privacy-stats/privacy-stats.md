---
title: Privacy Stats
---

## Requests:
### `stats_getData` 
- {@link "NewTab Messages".StatsGetDataRequest}
- Used to fetch the initial data (during the first render)
- returns {@link "NewTab Messages".PrivacyStatsData}

## Subscriptions:
### `stats_onDataUpdate` 
- {@link "NewTab Messages".StatsOnDataUpdateSubscription}.
- The tracker/company data used in the feed.
- returns {@link "NewTab Messages".PrivacyStatsData}
 
### `stats_showMore` 
- {@link "NewTab Messages".StatsShowMoreNotification}
- Sent when the user chooses to show more stats (eg: more than the default 5)
### `stats_showLess` 
- {@link "NewTab Messages".StatsShowLessNotification}
- Sent when the user chooses to show less stats (eg: from a long list back to the default)

## Example:

Note: The frontend will re-order the list based on the following two rules:

* First, descending order, from the highest count to lowest
* Second, the special entry `__other__` will always be placed at the end.

So, the following input is fine, no need for the native side to put the list into any order 

```json
{
  "totalCount": 12345,
  "trackerCompanies": [
    { "displayName": "__other__", "count": 89901 },
    { "displayName": "Tracker Co. C", "count": 91011 },
    { "displayName": "Tracker Co. A", "count": 1234 },
    { "displayName": "Tracker Co. B", "count": 5678 }
  ]
}
```

The following examples show the data types in JSON format (these are type-checked, so can be replied upon)
[messages/new-tab/examples/stats.js](../../messages/examples/stats.js)

