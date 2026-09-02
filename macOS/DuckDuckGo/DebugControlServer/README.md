# Debug Control Server

A loopback-only HTTP control surface for driving a locally built macOS debug browser from the command
line. It exists so that web-compat problems can be investigated with browser-level observability
(navigations, tracker detection, console, resource timing) instead of page-world instrumentation.

Every file in this directory except `Tab+DebugControlServer.swift` is wrapped in `#if DEBUG`, and that
one file's DEBUG branch is the only thing it contains — `DEBUG` is defined for the `Debug` and `CI`
configurations only (`macOS/Configuration/Common.xcconfig`), so none of this can ship in `Release`,
`Review` or `Alpha`.

## Running it

The server starts automatically at the end of `applicationDidFinishLaunching` in debug builds.

- Port: **8788**, overridable with the `DDG_CONTROL_PORT` environment variable. `DDG_CONTROL_PORT=0`
  disables the server.
- Bound to **127.0.0.1 only** (not `::1`).
- Note the WebDriver automation server (`-automationPort`) also defaults to 8788; if you run both, give
  one of them a different port.

Confirm it is up:

```sh
curl -s http://127.0.0.1:8788/status
```

Every response is `application/json` and is either `{"ok": true, ...}` or `{"ok": false, "error": "..."}`.
All request bodies are JSON; `GET` endpoints take the same names as query parameters.

All handlers act on the **selected tab of the last key window** unless stated otherwise.

## Endpoints

### `GET /status`

```sh
curl -s http://127.0.0.1:8788/status
```

```json
{"ok": true, "serverVersion": 1, "appVersion": "1.206.0", "buildNumber": "806",
 "bundleIdentifier": "com.duckduckgo.macos.browser.debug", "windowCount": 1, "isLoading": false,
 "tabs": [{"index": 0, "uuid": "…", "title": "…", "url": "https://…", "isSelected": true, "isPinned": false}]}
```

`index` is the position in a flat list of pinned tabs followed by unpinned tabs — the same index
`POST /tab` takes.

### `POST /navigate`

```sh
curl -s -X POST http://127.0.0.1:8788/navigate -d '{"url":"https://luna.amazon.com/","wait":true,"timeout":45}'
```

```json
{"ok": true, "url": "https://luna.amazon.com/", "waited": true, "settled": true}
```

Returns as soon as the load is requested unless `"wait": true`, in which case it polls `Tab.isLoading`
until the navigation settles or `timeout` (default 30) seconds elapse. `settled` is `false` on timeout.
`wait` only tracks the main frame load — poll `/console` or `/network` for anything later than that.

### `POST /eval`

```sh
curl -s -X POST http://127.0.0.1:8788/eval \
  -d '{"js":"const r = await fetch(location.href); return r.status;","world":"isolated"}'
```

```json
{"ok": true, "world": "isolated", "result": 200}
```

- `world`: `"page"` (default, the page's main content world) or `"isolated"`
  (`WKContentWorld.defaultClient` — the world content-scope-scripts runs in).
- Runs through `callAsyncJavaScript`, so `await` works and a returned promise is awaited.
- A snippet containing a `return` statement is used as a function body verbatim; anything else is
  wrapped as `return (…)`. Force either behaviour with `"expression": true|false`.
- JS exceptions come back as `{"ok": false, "error": "…"}`, never as a crash.

### `GET /console`

```sh
curl -s 'http://127.0.0.1:8788/console?since=1788325888215&clear=1'
```

```json
{"ok": true, "count": 2, "messages": [
  {"level": "error", "text": "…", "url": "https://…", "frame": "main", "line": 0, "column": 0,
   "source": "", "ts": 1788325888215}]}
```

`level` is the `console` method name, or `uncaught` / `unhandledrejection`. `ts` is milliseconds since
the epoch; `since` returns only entries strictly newer. `clear=1` empties the buffer after reading.

Implemented with a `documentStart`, all-frames user script injected into the isolated world that wraps
`console.*` and listens for `error` / `unhandledrejection`. It is installed when the server starts and
whenever a tab is first seen, so messages logged before that are not captured — reload after starting.

### `GET /network`

```sh
curl -s 'http://127.0.0.1:8788/network?since=…&clear=1'
```

```json
{"ok": true, "count": 125, "requests": [
  {"url": "https://…", "method": "GET", "status": 200, "initiator": "navigation-response",
   "resourceType": "document", "redirectedFrom": null, "blocked": false, "ts": 1788325945000}]}
```

Entries are flat and append-only; a single request can produce more than one entry. `initiator` says
which source saw it:

| `initiator` | source | what it covers |
|---|---|---|
| `navigation-action` | `NavigationResponder.decidePolicy(for navigationAction:)` | main frame and iframe document navigations, with `navigationType` and `identifier` |
| `navigation-response` | `decidePolicy(for navigationResponse:)` | the same navigations with `status` and `mimeType` |
| `redirect` | `didReceiveRedirect` | server/client redirects, with `redirectedFrom` |
| `navigation-failed` | `navigation(_:didFailWith:)` | failed navigations, with `error` |
| `content-scope-scripts` | `Tab.trackersPublisher` | every resource content-scope-scripts observes: `blocked`, `reason`, `entity`, `pageUrl` |
| `resource-timing` | `PerformanceObserver` in the injected script | every page-context subresource: `status` (from `responseStatus`), `duration`, `transferSize` |

`status` is `-1` when the source does not know it.

**What this does not see:** requests issued from a Web Worker or by WebKit itself. Neither the
navigation delegate, content-scope-scripts nor Resource Timing observes them. To capture those, route
the web view through an external proxy — the app already supports
`-webViewProxy socks5://127.0.0.1:<port> -acceptInsecureCerts true` alongside `-automationPort` and an
`AUTOMATION_TOKEN` env var (see `LaunchOptionsHandler` and `WKWebViewConfigurationExtensions`), which
points `WKWebsiteDataStore.proxyConfigurations` at a loopback proxy such as mitmproxy.

### `GET /protections`, `POST /protections`

```sh
curl -s 'http://127.0.0.1:8788/protections?domain=luna.amazon.com'
curl -s -X POST http://127.0.0.1:8788/protections -d '{"domain":"luna.amazon.com","enabled":false}'
```

```json
{"ok": true, "domain": "luna.amazon.com", "isProtected": true, "isUserUnprotected": false,
 "isTempUnprotected": false, "userUnprotectedDomains": []}
```

`domain` defaults to the selected tab's host. `POST` is the same call the shield toggle makes
(`userEnabledProtection` / `userDisabledProtection` plus `scheduleCompilation()`); it does not fire the
dashboard pixels and does not reload the tab, so reload once the rules have recompiled.

### `GET /config`

```sh
curl -s 'http://127.0.0.1:8788/config?domain=luna.amazon.com'
curl -s 'http://127.0.0.1:8788/config?feature=webCompat&domain=luna.amazon.com'
```

Without `feature`, a summary of every feature in the privacy configuration currently in effect:

```json
{"ok": true, "domain": "luna.amazon.com", "version": "…", "identifier": "…", "isProtected": true,
 "userUnprotectedDomains": [], "unprotectedTemporaryMatches": [],
 "features": {"webCompat": {"state": "enabled", "matchedExceptions": [], "enabledForDomain": true}}}
```

With `feature`, the full entry for one feature plus the overrides that matched the domain:

```json
{"ok": true, "domain": "luna.amazon.com", "feature": "webCompat", "state": "enabled",
 "matchedExceptions": [],
 "matchedDomainOverrides": [{"domain": ["www.cbsnews.com", "myhome.experian.co.uk", "luna.amazon.com"],
                             "patchSettings": [{"op": "replace", "path": "/messageHandlers/state", "value": "enabled"}]}],
 "settings": {...}, "subfeatures": {...}, "isUserUnprotected": false, "isTempUnprotected": false}
```

Read from the raw `PrivacyConfigurationManaging.currentConfig` JSON, because content-scope-scripts-only
features such as `webCompat` have no `PrivacyFeature` enum case. `matchedDomainOverrides` matches
`settings.domains[].domain` (string or array) against the domain, including subdomains and `<all>`.

### `POST /config`

```sh
curl -s -X POST http://127.0.0.1:8788/config \
  -d '{"path":"/Users/me/code/duckduckgo/privacy-configuration/generated/v4/macos-config.json"}'
curl -s -X POST http://127.0.0.1:8788/config -d '{"reset":true}'
```

```json
{"ok": true, "path": "/Users/…/macos-config.json", "bytes": 495758, "etag": "debug-1788325945753",
 "version": 1788334981566, "featureCount": 160,
 "note": "user scripts regenerated; open a new tab to run against this configuration"}
```

Swaps the in-memory privacy configuration for one read from disk, so a candidate change to the
privacy-configuration repo can be exercised before it ships. Build the file with `npm run build` in that
repo; the path must be absolute.

It calls `PrivacyConfigurationManaging.reload`, then `scheduleCompilation()` for the content blocking
rules, then posts `contentScopeDebugStateDidChange`. The notification is what actually gets the new
config into the page: `UserContentUpdating` only rebuilds the user scripts when
`ContentBlockerRulesManager` emits, and a config swap that compiles to the same rules produces no such
event — without it the tab keeps running content-scope-scripts with the previous configuration.

A config that fails to parse leaves the manager on its embedded fallback and comes back as an error.
`{"reset": true}` drops the override (back to the embedded config); the next scheduled config refresh
overwrites either state, so re-POST after a long session. `GET /config?feature=…` confirms what the
manager now holds.

**Open a new tab to exercise the change.** A tab keeps the user scripts it was given, so reloading an
existing one re-runs the previous configuration — `POST /tab/new` is what picks up the regenerated
scripts.

### `POST /screenshot`

```sh
curl -s -X POST http://127.0.0.1:8788/screenshot
```

```json
{"ok": true, "path": "/var/folders/…/T/ddg-debug-1788325945753.png", "bytes": 131730}
```

PNG from `takeSnapshot`, written to the temporary directory. Pass an absolute `"path"` to choose the
destination.

### `POST /reload`, `POST /clear-data`

```sh
curl -s -X POST http://127.0.0.1:8788/reload -d '{"bypassCache":true}'
curl -s -X POST http://127.0.0.1:8788/clear-data -d '{"domain":"luna.amazon.com"}'
```

```json
{"ok": true, "bypassCache": true}
{"ok": true, "cleared": "luna.amazon.com", "records": ["luna.amazon.com"]}
```

Omit `domain` (or pass `"all"`) to clear the whole data store for the selected tab's session.

### `GET /source`

```sh
curl -s http://127.0.0.1:8788/source
```

```json
{"ok": true, "bytes": 964, "html": "<html …>"}
```

Over 256KB the HTML is written to a file instead: `{"ok": true, "path": "/var/folders/…/T/ddg-debug-….html", "bytes": 1048576}`.

### `POST /ua`

```sh
curl -s -X POST http://127.0.0.1:8788/ua -d '{"value":"test-agent/1.0"}'
```

Sets `webView.customUserAgent`. `Tab.decidePolicy(for:preferences:)` re-applies `UserAgent.for(url)` on
the next main frame navigation, so set this **after** navigating. Pass `""` to clear.

### `POST /tab`, `POST /tab/new`

```sh
curl -s -X POST http://127.0.0.1:8788/tab -d '{"index":0}'
curl -s -X POST http://127.0.0.1:8788/tab/new -d '{"url":"https://example.org/"}'
```

```json
{"ok": true, "index": 0, "uuid": "…", "url": "https://…"}
```

`index` is the `/status` index. `url` is optional for `/tab/new`.

### `GET /userscripts`

```sh
curl -s http://127.0.0.1:8788/userscripts
```

```json
{"ok": true, "count": 4, "wkUserScriptCount": 6, "userScripts": [
  {"type": "ContentScopeUserScript", "sourceLength": 990581, "injectionTime": "documentStart",
   "forMainFrameOnly": false, "world": "isolated", "messageNames": ["contentScopeScriptsIsolated"]}]}
```

`userScripts` is what the DDG pipeline installed; `wkUserScriptCount` is WebKit's total, which also
includes web extension scripts and this server's own page observer.

## Implementation notes

- `DebugControlServer` — `NWListener` on `127.0.0.1`, one request per connection, `Connection: close`.
- `DebugControlHTTP` — request parsing (buffered until `Content-Length` is satisfied) and response encoding.
- `DebugControlRouter` — all endpoints; everything runs on the main actor.
- `DebugControlRecorder` — per-tab console and network ring buffers (5,000 and 20,000 entries), the
  `WKScriptMessageHandler` for the page observer, the `Tab.trackersPublisher` subscription, and the
  passive `NavigationResponder`.
- `DebugControlPageObserverScript` — the injected JS.
- `Tab+DebugControlServer` — the single hook into `Tab+Navigation.swift`'s responder list; returns `nil`
  outside DEBUG.

The recorder is inert until the server starts, so debug builds with `DDG_CONTROL_PORT=0` behave exactly
as before.
