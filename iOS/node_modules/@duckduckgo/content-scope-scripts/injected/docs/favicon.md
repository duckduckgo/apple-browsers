---
title: Favicon Monitor
---

# Favicon Monitor

Reports the presence of favicons on page-load, and optionally when they change.

## Notifications

### `faviconFound`

- {@link "Favicon Messages".FaviconFoundNotification}
- Sent on page load, sends {@link "Favicon Messages".FaviconFound}

**Example**

```json
{
    "favicons": [
        {
            "href": "favicon.png",
            "rel": "stylesheet"
        }
    ],
    "documentUrl": "https://example.com"
}
```

## Remote Config

## Enabled (default)

{@includeCode ../integration-test/test-pages/favicon/config/favicon-enabled.json}

### Disable the monitor only.

To only receive the initial payload and nothing more (to mimic the old behavior),
you can set `monitor: false` in the remote config, and it will not install the Mutation Observer.

{@includeCode ../integration-test/test-pages/favicon/config/favicon-monitor-disabled.json}
