# Adding a feature to the JS Bridge Playground

This debug tool exercises a feature's JS bridge inside an in-app WKWebView. Only Subscription is wired up today. Adding another feature is one new type plus one line in the debug menu.

## How it works

The playground attaches a feature's `UserScript`(s) to a fresh `WKWebView` and loads an HTML harness via `loadHTMLString(_:baseURL:)`. The `baseURL` is set to the feature's expected origin so each subfeature's `messageOriginPolicy` accepts the page. The page exposes a method field, a JSON params field, a Send button, and a response log.

The native side never inspects the response — JS captures it directly from the `Promise` returned by `window.webkit.messageHandlers.<handler>.postMessage(...)` and renders it in the log. No log scraping is needed.

## The minimum recipe

Implement `JSBridgePlaygroundFeature` and surface it from `DebugScreensViewModel+Screens.swift`.

```swift
struct MyFeaturePlaygroundFeature: JSBridgePlaygroundFeature {

    let displayName = "MyFeature"

    // window.webkit.messageHandlers.<messageHandlerName>
    let messageHandlerName = MyFeatureUserScript.context

    // payload.context — usually the same as messageHandlerName
    let messageContext = MyFeatureUserScript.context

    // payload.featureName — the subfeature constant declared by the feature
    let featureName = MyFeatureSubfeatureConstants.featureName

    // Origin used as baseURL for loadHTMLString. Must satisfy the subfeature's
    // messageOriginPolicy (typically a HostnameMatchingRule.makeExactRule).
    var baseURL: URL {
        URL(string: "https://duckduckgo.com/myfeature")!
    }

    // Quick-fill chips on the page. sampleParamsJSON pre-populates the params field.
    var knownMethods: [JSBridgePlaygroundMethod] {
        [
            JSBridgePlaygroundMethod(name: "doSomething", sampleParamsJSON: "{}"),
            JSBridgePlaygroundMethod(name: "doSomethingElse", sampleParamsJSON: #"{"foo": "bar"}"#)
        ]
    }

    @MainActor
    func makeUserScripts() -> [UserScript] {
        let userScript = MyFeatureUserScript()
        let subFeature = MyFeatureSubfeature(/* real dependencies */)
        userScript.registerSubfeature(delegate: subFeature)
        return [userScript]
    }
}
```

Then in `DebugScreensViewModel+Screens.swift`:

```swift
.controller(title: "JS Bridge Playground (MyFeature)", { _ in
    return JSBridgePlaygroundViewController(feature: MyFeaturePlaygroundFeature())
}),
```

## Things to get right

### `baseURL` must satisfy the origin policy

Subfeatures gate inbound messages with `messageOriginPolicy`. Most use `HostnameMatchingRule.makeExactRule(for:)` against a base URL. Set the playground feature's `baseURL` to a URL whose scheme + host (and where relevant, port) match the subfeature's expected origin. `WKWebView.loadHTMLString(_:baseURL:)` reports that URL as the page origin to the script.

If the page's `window.webkit.messageHandlers.<handler>` is `undefined`, the user script is not attaching — either the handler name is wrong, or the script registration failed at construction time. If `postMessage` rejects with an origin error, the `baseURL` doesn't match the policy.

### Dependency wiring

Each subfeature has its own constructor. Mirror the production wiring as closely as possible — the playground exists to test the bridge layer against real handlers, so injecting real dependencies (where safe in a debug surface) gives the most faithful behavior. `SubscriptionBridgePlaygroundFeature.swift` (alongside this doc) is a worked example of a heavy-dependency case.

### Make the user-script instances retained

`JSBridgePlaygroundViewController` already stores the returned `[UserScript]` in a `private var` so the wrapper objects (and the broker → subfeature retention chain) outlive `makeUserScripts()`. If you add an alternative entry point, mirror this — `WKUserContentController.addUserScript(_:)` retains the underlying `WKUserScript`, but not the Swift `UserScript` wrapper.

## Push-style messages (native -> JS)

This UI is one-shot request/response. Methods like `pushPurchaseUpdate` are fire-and-forget native -> JS dispatches against a live webview and aren't surfaced by the current UI. Exercising them needs a JS-side listener registered on the page plus a native trigger; add it as a separate code path if you need it.

## Features still to plumb

These all expose JS bridges and are candidates for follow-up registrations:

- `AIChat` — `iOS/DuckDuckGo/AIChat/UserScript/AIChatUserScript.swift`
- `AIChatSuggestions` — `SharedPackages/AIChat/.../AIChatSuggestionsUserScript.swift`
- `DuckAiNativeStorage` — `SharedPackages/AIChat/.../DuckAiNativeStorageUserScript.swift`
- `AIChatDataClearing` — `SharedPackages/AIChat/.../AIChatDataClearingUserScript.swift`
- `PageContext` — `iOS/DuckDuckGo/AIChat/UserScript/PageContextUserScript.swift`
- `DuckPlayer (player + youtube variants)` — `DuckPlayerUserScriptPlayer.swift`, `DuckPlayerUserScriptYouTube.swift`, `YoutubeOverlayUserScript.swift`, `YoutubePlayerUserScript.swift`
- `IdentityTheftRestoration` — `iOS/DuckDuckGo/Subscription/UserScripts/IdentityTheftRestorationPagesFeature.swift`
- `SERPSettings` — `SharedPackages/SERPSettings/.../SERPSettingsUserScript.swift`
- `DBP` — `SharedPackages/DataBrokerProtectionCore/.../DBPUICommunicationLayer.swift`
- `SpecialErrorPages` — `SharedPackages/BrowserServicesKit/.../SpecialErrorPageUserScript.swift`
- `BrokenSiteReporting` — `SharedPackages/BrowserServicesKit/.../BreakageReportingSubfeature.swift`
- `WebTelemetry` — `SharedPackages/BrowserServicesKit/.../WebTelemetryUserScript.swift`

## Caveats

- **State is real.** Calls hit the real `SubscriptionManager`, real network, real keychain, etc. Don't fire destructive methods against a signed-in tester account.
- **Tab-coupled features.** Anything that relies on a `Tab` or surrounding navigation chain may need a stub or simplified factory for the playground surface.
- **Internal-only.** Don't surface this outside debug builds.
