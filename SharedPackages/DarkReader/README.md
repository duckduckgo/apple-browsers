# DarkReader Integration

This directory contains [DarkReader](https://github.com/darkreader/darkreader) packaged as a minimal Manifest V3 web extension for use with `WKWebExtension` on iOS (18.4+).

## Current Version

**DarkReader v4.9.121**

## How It Works

Instead of bundling the full DarkReader browser extension (which depends on Chrome-specific APIs like `chrome.alarms`, `chrome.fontSettings`, `chrome.storage`, and `chrome.tabs`), we use the **DarkReader npm API build**. This is a self-contained library that performs all dark theme generation within the content script — no complex background service worker logic or extension messaging required.

The extension consists of 4 files:

| File | Purpose |
|---|---|
| `manifest.json` | MV3 manifest with minimal permissions |
| `darkreader-api.js` | DarkReader npm API library (~328KB, built via `npm run api`) |
| `content-script.js` | Calls `DarkReader.auto()` to follow the system color scheme |
| `background.js` | Minimal service worker that silently absorbs internal `chrome.runtime` messages |

### `DarkReader.auto()`

The `auto()` function monitors the `prefers-color-scheme: dark` media query. When the device is in dark mode, DarkReader generates and injects a dark theme for the page. When the device switches to light mode, the dark theme is removed. This maps naturally to the app's "Adaptive Dark Mode" setting.

### Why the npm API instead of the full extension?

The full DarkReader Chrome MV3 extension relies on several Chrome extension APIs that are either unsupported or behave differently in Safari's `WKWebExtension`:

- `chrome.alarms` — timer management
- `chrome.fontSettings` — system font detection
- `chrome.storage` — persistent settings
- `chrome.tabs` — tab management

The npm API build avoids all of these. It stubs `chrome.runtime.sendMessage` internally to handle cross-origin CSS fetching directly via `fetch()` from the content script, using the extension's `host_permissions` for CORS access.

## Updating DarkReader

Run the update script from the repository root:

```bash
./SharedPackages/DarkReader/update-darkreader.sh
```

Or specify a version:

```bash
./SharedPackages/DarkReader/update-darkreader.sh v4.9.130
```

The script clones the DarkReader repository, builds the npm API library, copies it into the extension, and updates `manifest.json` with the new version number.

## Native Integration

The extension is loaded by `MainCoordinator` on iOS:

- **Install**: when `isAdaptiveDarkModeEnabled` is `true` and web extensions are enabled
- **Uninstall**: when the setting is toggled off
- **Blocked domains**: `duckduckgo.com`, `apple.com` (and subdomains)

The `WKWebExtension` framework reads `manifest.json`, registers the content scripts, and grants `host_permissions` via `WebExtensionLoader`.
