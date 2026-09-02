# BrowserMCP

`ddg-browser-mcp` is a [Model Context Protocol](https://modelcontextprotocol.io) server that lets AI agents
(Claude Code, Cursor, etc.) drive a Debug or Review build of the DuckDuckGo browser.

It contains **no browser code**. Every tool is a thin adapter over the HTTP automation server that already
ships in Debug/Review builds (`SharedPackages/AutomationServer`), the same server used by `ddgdriver` in
[shared-web-tests](https://github.com/duckduckgo/shared-web-tests) and by the crossbench harness. Anything
added to the browser for WebDriver is therefore available to agents, and vice versa, on both macOS and iOS.

## Build

```sh
swift build -c release --package-path SharedPackages/BrowserMCP
# binary: SharedPackages/BrowserMCP/.build/release/ddg-browser-mcp
```

This package is intentionally **not** part of `DuckDuckGo.xcworkspace`, so the MCP SDK and its dependencies
never enter the app targets or the workspace's `Package.resolved`.

## Configure

The server is configured through environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `DDG_AUTOMATION_PORT` | `8788` | Port the browser listens on (`-automationPort`) |
| `DDG_APP_PATH` | none | `DuckDuckGo.app` used by `browser_launch` |
| `AUTOMATION_TOKEN` | none | Optional bearer token; forwarded to the browser on launch and sent with every request |

With Claude Code, for example:

```sh
claude mcp add ddg-browser \
  -e DDG_APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/DuckDuckGo.app" \
  -- /path/to/ddg-browser-mcp
```

Either let the agent call `browser_launch`, or start the browser yourself:

```sh
/path/to/DuckDuckGo.app/Contents/MacOS/DuckDuckGo -automationPort 8788
```

The automation server only starts in Debug and Review builds.

## Tools

| Tool | Automation route(s) |
|---|---|
| `browser_launch` | launches the app, polls `/contentBlockerReady` |
| `browser_navigate` | `POST /navigate`, then `/getUrl` + `/getTitle` |
| `browser_get_url` / `browser_get_title` | `GET /getUrl` / `GET /getTitle` |
| `browser_go_back` / `browser_go_forward` | `POST /goBack` / `POST /goForward` |
| `browser_scroll` | `POST /scroll?x=&y=` |
| `browser_execute` | `POST /execute?script=&args=` |
| `browser_screenshot` | `GET /screenshot[?rect=]`, returned as MCP image content |
| `browser_tab_list` | `GET /getTabs` |
| `browser_tab_new` | `POST /newWindow` (+ `/navigate`) |
| `browser_tab_switch` | `POST /switchToWindow?handle=` |
| `browser_tab_close` | (`/switchToWindow`) + `POST /closeWindow` |
| `browser_clear_website_data` | `POST /clearWebsiteData` (requires `AUTOMATION_TOKEN`) |
| `browser_shutdown` | `POST /shutdown` |

`browser_execute` is the escape hatch: the script is the body of an async function run in the page, so agents
can read the DOM, click elements, or wait for conditions without new native code.

## Adding a capability

1. Add the member to `BrowserAutomationProvider` in `SharedPackages/AutomationServer`, with a default
   implementation where one is possible (`goBack`, `scroll` and `getAllTabs` have them).
2. Add the route to `AutomationServerCore.handlePath` and a test in `RouteHandlerTests`.
3. Override the member in `MacOSAutomationProvider` / `IOSAutomationProvider` if the default is not enough.
4. Add a tool in `BrowserTools.definitions` and a case in `BrowserTools.handle`, with a test in
   `BrowserToolsTests` using `FakeTransport`.

## Why a separate process?

Hosting MCP inside the app would let agents connect without a helper binary, but it pulls the MCP SDK and
swift-nio into the app targets, requires an app rebuild for every tool schema change, raises the iOS floor
to 16, and cannot start the browser because the server only exists once the app is running.
`BrowserMCPTools` is a library separate from the executable, so hosting the same tool definitions in-app
over the SDK's HTTP transport later is a transport swap, not a rewrite.

## Test

```sh
swift test --package-path SharedPackages/AutomationServer
swift test --package-path SharedPackages/BrowserMCP
```
