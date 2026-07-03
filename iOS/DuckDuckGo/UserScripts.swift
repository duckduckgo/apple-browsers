//
//  UserScripts.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AIChat
import BrowserServicesKit
import Core
import CoreLocation
import os.log
import Foundation
import Persistence
import PrivacyConfig
import SERPSettings
import SpecialErrorPages
import Subscription
import TrackerRadarKit
import UserScript
import WebExtensions
import WebKit

final class UserScripts: UserScriptsProvider {

    let autofillUserScript: AutofillUserScript
    let loginFormDetectionScript: LoginFormDetectionUserScript?
    let contentScopeUserScript: ContentScopeUserScript
    let contentScopeUserScriptIsolated: ContentScopeUserScript
    let autoconsentUserScript: AutoconsentUserScript
    let aiChatUserScript: AIChatUserScript
    let subscriptionUserScript: SubscriptionUserScript
    let subscriptionNavigationHandler: SubscriptionURLNavigationHandler
    let serpSettingsUserScript: SERPSettingsUserScript
    let duckAiNativeStorageUserScript: DuckAiNativeStorageUserScript?
    let pageContextUserScript: PageContextUserScript

    var specialPages: SpecialPagesUserScript?
    var duckPlayer: DuckPlayerControlling? {
        didSet {
            initializeDuckPlayer()
        }
    }
    var youtubeOverlayScript: YoutubeOverlayUserScript?
    var youtubePlayerUserScript: YoutubePlayerUserScript?
    var specialErrorPageUserScript: SpecialErrorPageUserScript?

    private(set) var faviconScript = FaviconUserScript()
    private(set) var findInPageScript = FindInPageUserScript()
    private(set) var fullScreenVideoScript = FullScreenVideoUserScript()
    // GEOLOCATION SPIKE — per-tab geolocation shim (see bottom of this file)
    private(set) var geolocationUserScript = GeolocationUserScript()
    private(set) var printingSubfeature = PrintingSubfeature()
    private(set) var trackerProtectionSubfeature = TrackerProtectionSubfeature()
    let webEventsSubfeature: WebEventsSubfeature

    private let isAutoconsentExtensionAvailable: Bool

    init(with sourceProvider: ScriptSourceProviding,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         keyValueStore: ThrowingKeyValueStoring,
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = nil,
         aiChatDebugSettings: AIChatDebugSettingsHandling = AIChatDebugSettings(),
         adBlockingAvailability: AdBlockingAvailabilityProviding) {

        isAutoconsentExtensionAvailable = sourceProvider.webExtensionAvailability?.isAutoconsentExtensionAvailable ?? false

        autofillUserScript = AutofillUserScript(scriptSourceProvider: sourceProvider.autofillSourceProvider)
        autofillUserScript.sessionKey = sourceProvider.contentScopeProperties.sessionKey

        loginFormDetectionScript = sourceProvider.loginDetectionEnabled ? LoginFormDetectionUserScript() : nil
        do {
            let configGenerator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: AppDependencyProvider.shared.featureFlagger,
                                                                                privacyConfigurationManager: sourceProvider.privacyConfigurationManager,
                                                                                excludedFeatures: [PrivacyFeature.autoconsent.rawValue])
            let isolatedConfigGenerator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: AppDependencyProvider.shared.featureFlagger,
                                                                                        privacyConfigurationManager: sourceProvider.privacyConfigurationManager)
            contentScopeUserScript = try ContentScopeUserScript(sourceProvider.privacyConfigurationManager,
                                                                properties: sourceProvider.contentScopeProperties,
                                                                scriptContext: .contentScope(surrogateTrackerData: sourceProvider.trackerProtectionDataSource?.surrogateFilteredTrackerData),
                                                                allowedNonisolatedFeatures: [PageContextUserScript.featureName, PrintingSubfeature.featureNameValue, TrackerProtectionSubfeature.featureNameValue],
                                                                privacyConfigurationJSONGenerator: configGenerator)
            contentScopeUserScriptIsolated = try ContentScopeUserScript(sourceProvider.privacyConfigurationManager,
                                                                        properties: sourceProvider.contentScopeProperties,
                                                                        scriptContext: .contentScopeIsolated,
                                                                        privacyConfigurationJSONGenerator: isolatedConfigGenerator)
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to initialize ContentScopeUserScript: \(error)")
        }
        autoconsentUserScript = AutoconsentUserScript(
            config: sourceProvider.privacyConfigurationManager.privacyConfig,
            webExtensionAvailability: sourceProvider.webExtensionAvailability,
            featureFlagger: featureFlagger
        )

        // `setupSucceeded == nil` (setup still in flight) is treated as "available"
        // so the launch path is not blocked. Only force the JS fallback when a
        // permanent setup failure has been observed.
        let isNativeStorageBridgeAvailable = featureFlagger.isFeatureOn(.aiChatNativeStorage)
            && duckAiNativeStorageHandler != nil
            && duckAiNativeStorageHandler?.setupSucceeded != false
        let experimentalManager: ExperimentalAIChatManager = .init(featureFlagger: featureFlagger)
        let aiChatSettings = AIChatSettings()
        let aiChatScriptHandler = AIChatUserScriptHandler(experimentalAIChatManager: experimentalManager,
                                                          syncHandler: AIChatSyncHandler(sync: sourceProvider.sync,
                                                                                         httpRequestErrorHandler: sourceProvider.syncErrorHandler.handleAiChatsError),
                                                          featureFlagger: featureFlagger,
                                                          isNativeStorageBridgeAvailable: isNativeStorageBridgeAvailable)
        aiChatUserScript = AIChatUserScript(handler: aiChatScriptHandler,
                                            debugSettings: aiChatDebugSettings)
        serpSettingsUserScript = SERPSettingsUserScript(serpSettingsProviding: SERPSettingsProvider(aiChatProvider: aiChatSettings))

        if isNativeStorageBridgeAvailable,
           let duckAiNativeStorageHandler {
            var originRules: [HostnameMatchingRule] = [
                .exactOrSubdomain(hostname: "duck.ai"),
            ]
            if let debugHostname = aiChatDebugSettings.messagePolicyHostname {
                originRules.append(.exact(hostname: debugHostname))
            }
            duckAiNativeStorageUserScript = DuckAiNativeStorageUserScript(
                handler: duckAiNativeStorageHandler,
                originRules: originRules,
                pixelFiring: DuckAiNativeStoragePixelAdapter()
            )
        } else {
            duckAiNativeStorageUserScript = nil
        }

        pageContextUserScript = PageContextUserScript()

        subscriptionNavigationHandler = SubscriptionURLNavigationHandler()
        let subscriptionFeatureFlagAdapter = SubscriptionUserScriptFeatureFlagAdapter(featureFlagger: featureFlagger)
        subscriptionUserScript = SubscriptionUserScript(
            platform: .ios,
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
            featureFlagProvider: subscriptionFeatureFlagAdapter,
            navigationDelegate: subscriptionNavigationHandler,
            debugHost: aiChatDebugSettings.messagePolicyHostname)
        let youTubeAdBlockingStorage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> = keyValueStore.throwingKeyedStoring()
        webEventsSubfeature = WebEventsSubfeature(
            isUserOptedIn: {
                let analyticsEnabled = (try? youTubeAdBlockingStorage.value(for: \.youTubeAnalyticsEnabled)) ?? false
                return adBlockingAvailability.isEnabled && analyticsEnabled
            },
            onEvent: { type, loginState in
                guard let pixel = Pixel.Event.adBlockingDetectedEvent(type: type) else { return }
                DailyPixel.fire(
                    pixel: pixel,
                    withAdditionalParameters: ["loginState": loginState.rawValue]
                )
            }
        )

        contentScopeUserScriptIsolated.registerSubfeature(delegate: faviconScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: webEventsSubfeature)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: aiChatUserScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: subscriptionUserScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: serpSettingsUserScript)
        if let duckAiNativeStorageUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: duckAiNativeStorageUserScript)
        }
        contentScopeUserScript.registerSubfeature(delegate: printingSubfeature)
        contentScopeUserScript.registerSubfeature(delegate: pageContextUserScript)
        contentScopeUserScript.registerSubfeature(delegate: trackerProtectionSubfeature)

        // Special pages - Such as Duck Player
        specialPages = SpecialPagesUserScript()
        if let specialPages {
            userScripts.append(specialPages)
        }
        specialErrorPageUserScript = SpecialErrorPageUserScript(localeStrings: SpecialErrorPageUserScript.localeStrings(),
                                                                languageCode: Locale.current.languageCode ?? "en")
        specialErrorPageUserScript.map { specialPages?.registerSubfeature(delegate: $0) }
    }

    lazy var userScripts: [UserScript] = {
        var scripts: [UserScript?] = [
            findInPageScript,
            fullScreenVideoScript,
            geolocationUserScript, // GEOLOCATION SPIKE
            autofillUserScript,
            loginFormDetectionScript,
            contentScopeUserScript,
            contentScopeUserScriptIsolated
        ]

        if !isAutoconsentExtensionAvailable {
            scripts.insert(autoconsentUserScript, at: 1)
        }

        return scripts.compactMap { $0 }
    }()
    
    // Initialize DuckPlayer scripts
    private func initializeDuckPlayer() {
        if let duckPlayer {
            // Initialize scripts if nativeUI is disabled
            if !duckPlayer.settings.nativeUI {
                youtubeOverlayScript = YoutubeOverlayUserScript(duckPlayer: duckPlayer)
                youtubePlayerUserScript = YoutubePlayerUserScript(duckPlayer: duckPlayer)
                youtubeOverlayScript.map { contentScopeUserScriptIsolated.registerSubfeature(delegate: $0) }
                youtubePlayerUserScript.map { specialPages?.registerSubfeature(delegate: $0) }
            } else {
                // Initialize DuckPlayer UserScript
                let duckPlayerUserScript = DuckPlayerUserScriptYouTube(duckPlayer: duckPlayer)
                contentScopeUserScriptIsolated.registerSubfeature(delegate: duckPlayerUserScript)
            }
        }
    }
    
    @MainActor
    func loadWKUserScripts() async -> [WKUserScript] {
        return await withTaskGroup(of: WKUserScriptBox.self) { @MainActor group in
            var wkUserScripts = [WKUserScript]()
            userScripts.forEach { userScript in
                group.addTask { @MainActor in
                    await userScript.makeWKUserScript()
                }
            }
            for await result in group {
                wkUserScripts.append(result.wkUserScript)
            }

            return wkUserScripts
        }
    }

}

// MARK: - =========================================================================
// MARK: GEOLOCATION SPIKE  (throwaway — do not merge)
// MARK: =========================================================================
//
// Feasibility spike: control web geolocation on iOS by intercepting
// `navigator.geolocation` in an injected content script and bridging to
// CoreLocation. iOS WKWebView exposes no working geolocation-permission
// delegate, so this JS-shim path is the candidate. Everything geolocation-
// related lives in this section + a matching extension in TabViewController.swift.
//
// Wiring: `geolocationUserScript` is added to the `userScripts` array above,
// which injects the shim (document-start, all frames, PAGE content world) and
// registers the "geolocation" message handler in the same PAGE content world.
// TabViewController sets itself as the delegate and provides the webView.

/// A position or error to hand back to a single JS request/watch.
enum GeolocationEmission {
    /// Values map onto the W3C `GeolocationCoordinates`; `timestamp` is ms since epoch.
    case position(latitude: Double, longitude: Double, accuracy: Double,
                  altitude: Double?, altitudeAccuracy: Double?,
                  heading: Double?, speed: Double?, timestamp: Double)
    /// `code` is a W3C `GeolocationPositionError` code: 1 = PERMISSION_DENIED,
    /// 2 = POSITION_UNAVAILABLE, 3 = TIMEOUT.
    case error(code: Int, message: String)

    static func make(from location: CLLocation) -> GeolocationEmission {
        .position(latitude: location.coordinate.latitude,
                  longitude: location.coordinate.longitude,
                  accuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : 0,
                  altitude: location.verticalAccuracy > 0 ? location.altitude : nil,
                  altitudeAccuracy: location.verticalAccuracy > 0 ? location.verticalAccuracy : nil,
                  heading: location.course >= 0 ? location.course : nil,
                  speed: location.speed >= 0 ? location.speed : nil,
                  timestamp: location.timestamp.timeIntervalSince1970 * 1000)
    }
}

/// A decoded `getCurrentPosition`/`watchPosition` call from the page.
struct WebGeolocationRequest {
    let id: Int                 // unique per (tab) shim; also the JS watch id for watches
    let isWatch: Bool
    let enableHighAccuracy: Bool
    let timeout: Double?        // ms, nil == no timeout
    let maximumAge: Double      // ms
    let origin: String          // e.g. "https://example.com"
    let frameInfo: WKFrameInfo  // frame to push results back into
}

protocol GeolocationUserScriptDelegate: AnyObject {
    /// The page asked for a position. Call `emit` once (getCurrentPosition) or
    /// repeatedly (watchPosition). Runs on the main thread.
    func geolocationUserScript(_ script: GeolocationUserScript,
                               didRequestPositionFor request: WebGeolocationRequest,
                               emit: @escaping (GeolocationEmission) -> Void)
    /// The page called `clearWatch(id)`.
    func geolocationUserScript(_ script: GeolocationUserScript, didClearWatchWithID id: Int)
}

/// Injected shim + JS<->native bridge for the Geolocation API.
final class GeolocationUserScript: NSObject, UserScript {

    weak var delegate: GeolocationUserScriptDelegate?
    weak var webView: WKWebView?

    /// Per-tab CoreLocation access. Lazy so tabs that never touch geolocation
    /// never spin up a CLLocationManager.
    lazy var provider = WebGeolocationProvider()

    // Per-tab, in-memory permission cache + prompt coalescing (origin string keys).
    var grantedOrigins = Set<String>()
    var deniedOrigins = Set<String>()
    var pendingPrompts = [String: [(Bool) -> Void]]()

    // MARK: UserScript

    var injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    var forMainFrameOnly: Bool = false
    var messageNames: [String] = ["geolocation"]
    // MUST run in the page content world so the override is visible to page
    // scripts; registering here also puts the message handler in that world.
    var requiresRunInPageContentWorld: Bool { true }

    var source: String { Self.shimSource }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String,
              let id = (body["id"] as? NSNumber)?.intValue else { return }

        switch method {
        case "clearWatch":
            delegate?.geolocationUserScript(self, didClearWatchWithID: id)

        case "queryPermission":
            // navigator.permissions.query — answer from the per-origin cache.
            let origin = Self.origin(from: message.frameInfo)
            let state: String
            if grantedOrigins.contains(origin) {
                state = "granted"
            } else if deniedOrigins.contains(origin) {
                state = "denied"
            } else {
                state = "prompt"
            }
            dispatchPermission(state, forQueryID: id, in: message.frameInfo)

        case "getCurrentPosition", "watchPosition":
            let options = body["options"] as? [String: Any] ?? [:]
            let request = WebGeolocationRequest(
                id: id,
                isWatch: method == "watchPosition",
                enableHighAccuracy: (options["enableHighAccuracy"] as? Bool) ?? false,
                timeout: (options["timeout"] as? NSNumber)?.doubleValue,
                maximumAge: (options["maximumAge"] as? NSNumber)?.doubleValue ?? 0,
                origin: Self.origin(from: message.frameInfo),
                frameInfo: message.frameInfo)
            let frame = message.frameInfo
            delegate?.geolocationUserScript(self, didRequestPositionFor: request) { [weak self] emission in
                self?.dispatch(emission, forID: id, in: frame)
            }

        default:
            break
        }
    }

    // MARK: Native -> JS

    /// Push a result/error into the shim's dispatcher, in the page content world
    /// and the originating frame (so iframes work).
    private func dispatch(_ emission: GeolocationEmission, forID id: Int, in frame: WKFrameInfo) {
        let type: String
        let payload: [String: Any]
        switch emission {
        case let .position(lat, lon, acc, alt, altAcc, heading, speed, ts):
            type = "success"
            payload = [
                "latitude": lat,
                "longitude": lon,
                "accuracy": acc,
                "altitude": alt.map { $0 as Any } ?? NSNull(),
                "altitudeAccuracy": altAcc.map { $0 as Any } ?? NSNull(),
                "heading": heading.map { $0 as Any } ?? NSNull(),
                "speed": speed.map { $0 as Any } ?? NSNull(),
                "timestamp": ts
            ]
        case let .error(code, message):
            type = "error"
            payload = ["code": code, "message": message]
        }

        let js = "window.__ddgGeoDispatch && window.__ddgGeoDispatch(\(id), '\(type)', \(Self.jsonLiteral(payload)));"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, in: frame, in: .page, completionHandler: nil)
        }
    }

    /// Reply to a `navigator.permissions.query({name:'geolocation'})` call.
    private func dispatchPermission(_ state: String, forQueryID id: Int, in frame: WKFrameInfo) {
        let js = "window.__ddgGeoDispatch && window.__ddgGeoDispatch(\(id), 'permission', {state:'\(state)'});"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, in: frame, in: .page, completionHandler: nil)
        }
    }

    /// Broadcast a permission-state change so `PermissionStatus.onchange` fires
    /// (keeps the Permissions API in step with the user's allow/deny decision).
    func notifyPermissionState(_ state: String, in frame: WKFrameInfo) {
        let js = "window.__ddgGeoDispatch && window.__ddgGeoDispatch(0, 'permissionState', {state:'\(state)'});"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, in: frame, in: .page, completionHandler: nil)
        }
    }

    // MARK: Helpers

    private static func origin(from frame: WKFrameInfo) -> String {
        let origin = frame.securityOrigin
        let scheme = origin.`protocol`
        var value = scheme + "://" + origin.host
        if origin.port != 0 { value += ":\(origin.port)" }
        return value
    }

    private static func jsonLiteral(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    // MARK: The shim
    //
    // Runs at document-start in the page world before any page script. Replaces
    // navigator.geolocation with an object that forwards to native and resolves
    // page callbacks when native pushes results via __ddgGeoDispatch.
    private static let shimSource = """
    (function() {
        'use strict';
        if (window.__ddgGeoInstalled) { return; }
        window.__ddgGeoInstalled = true;

        var callbacks = {};   // id -> { success, error, isWatch }
        var nextId = 1;

        // Permissions API mirror: kept in sync with the native per-origin decision.
        var permStatuses = [];   // live PermissionStatus views for geolocation
        var permQueries = {};    // query id -> resolver
        var geoState = 'prompt'; // last known geolocation permission state

        function post(msg) {
            try { window.webkit.messageHandlers.geolocation.postMessage(msg); } catch (e) {}
        }

        function makePermissionStatus(initialState) {
            var listeners = [];
            var ps = {
                name: 'geolocation',
                state: initialState,
                onchange: null,
                addEventListener: function(type, fn) {
                    if (type === 'change' && typeof fn === 'function') { listeners.push(fn); }
                },
                removeEventListener: function(type, fn) {
                    if (type === 'change') { var i = listeners.indexOf(fn); if (i >= 0) { listeners.splice(i, 1); } }
                },
                dispatchEvent: function() { return true; }
            };
            ps._fire = function() {
                if (typeof ps.onchange === 'function') { try { ps.onchange({ type: 'change', target: ps }); } catch (e) {} }
                for (var i = 0; i < listeners.length; i++) { try { listeners[i].call(ps, { type: 'change', target: ps }); } catch (e) {} }
            };
            return ps;
        }

        function applyGeoState(newState) {
            var changed = (newState !== geoState);
            geoState = newState;
            for (var i = 0; i < permStatuses.length; i++) {
                permStatuses[i].state = newState;
                if (changed) { permStatuses[i]._fire(); }
            }
        }

        function toPosition(p) {
            return {
                coords: {
                    latitude: p.latitude,
                    longitude: p.longitude,
                    accuracy: p.accuracy,
                    altitude: (p.altitude === undefined ? null : p.altitude),
                    altitudeAccuracy: (p.altitudeAccuracy === undefined ? null : p.altitudeAccuracy),
                    heading: (p.heading === undefined ? null : p.heading),
                    speed: (p.speed === undefined ? null : p.speed)
                },
                timestamp: p.timestamp
            };
        }

        function toError(p) {
            return {
                code: p.code,
                message: p.message || '',
                PERMISSION_DENIED: 1,
                POSITION_UNAVAILABLE: 2,
                TIMEOUT: 3
            };
        }

        function normalizeOptions(options) {
            options = options || {};
            var timeout = null;
            if (typeof options.timeout === 'number' && isFinite(options.timeout)) {
                timeout = Math.max(0, options.timeout);
            }
            var maximumAge = 0;
            if (typeof options.maximumAge === 'number' && isFinite(options.maximumAge)) {
                maximumAge = Math.max(0, options.maximumAge);
            }
            return {
                enableHighAccuracy: !!options.enableHighAccuracy,
                timeout: timeout,
                maximumAge: maximumAge
            };
        }

        // Native calls this (page content world, originating frame).
        var dispatch = function(id, type, payload) {
            if (type === 'permissionState') { applyGeoState(payload.state); return; }
            if (type === 'permission') {
                var resolver = permQueries[id];
                if (resolver) { delete permQueries[id]; resolver(payload.state); }
                return;
            }
            var cb = callbacks[id];
            if (!cb) { return; }
            if (type === 'success') {
                if (!cb.isWatch) { delete callbacks[id]; }
                if (typeof cb.success === 'function') {
                    try { cb.success(toPosition(payload)); } catch (e) {}
                }
            } else if (type === 'error') {
                if (!cb.isWatch) { delete callbacks[id]; }
                if (typeof cb.error === 'function') {
                    try { cb.error(toError(payload)); } catch (e) {}
                }
            }
        };
        try {
            Object.defineProperty(window, '__ddgGeoDispatch', {
                value: dispatch, configurable: true, enumerable: false, writable: false
            });
        } catch (e) { window.__ddgGeoDispatch = dispatch; }

        var geolocation = {
            getCurrentPosition: function(success, error, options) {
                if (typeof success !== 'function') {
                    throw new TypeError("Failed to execute 'getCurrentPosition' on 'Geolocation': parameter 1 is not of type 'Function'.");
                }
                var id = nextId++;
                callbacks[id] = { success: success, error: (typeof error === 'function' ? error : null), isWatch: false };
                post({ method: 'getCurrentPosition', id: id, options: normalizeOptions(options) });
            },
            watchPosition: function(success, error, options) {
                if (typeof success !== 'function') {
                    throw new TypeError("Failed to execute 'watchPosition' on 'Geolocation': parameter 1 is not of type 'Function'.");
                }
                var id = nextId++;
                callbacks[id] = { success: success, error: (typeof error === 'function' ? error : null), isWatch: true };
                post({ method: 'watchPosition', id: id, options: normalizeOptions(options) });
                return id;
            },
            clearWatch: function(id) {
                if (callbacks[id]) { delete callbacks[id]; }
                post({ method: 'clearWatch', id: id });
            }
        };

        try {
            Object.defineProperty(navigator, 'geolocation', {
                value: geolocation, configurable: true, enumerable: true
            });
        } catch (e) {
            try { navigator.geolocation = geolocation; } catch (e2) {}
        }

        // Keep the Permissions API in sync with our native decision. Geolocation
        // is answered from native (cached per-origin state); onchange fires when
        // the user later grants/denies. Other permission names pass through.
        try {
            if (navigator.permissions && typeof navigator.permissions.query === 'function') {
                var originalQuery = navigator.permissions.query.bind(navigator.permissions);
                navigator.permissions.query = function(desc) {
                    if (desc && desc.name === 'geolocation') {
                        return new Promise(function(resolve) {
                            var ps = makePermissionStatus(geoState);
                            permStatuses.push(ps);
                            var qid = nextId++;
                            var settled = false;
                            permQueries[qid] = function(state) {
                                settled = true;
                                ps.state = state;
                                geoState = state;
                                resolve(ps);
                            };
                            post({ method: 'queryPermission', id: qid });
                            // Defensive: never hang the page if native doesn't answer.
                            setTimeout(function() {
                                if (!settled && permQueries[qid]) { delete permQueries[qid]; resolve(ps); }
                            }, 2000);
                        });
                    }
                    return originalQuery(desc);
                };
            }
        } catch (e) {}

        // Stop native watches when the document goes away (best-effort).
        window.addEventListener('pagehide', function() {
            for (var id in callbacks) {
                if (callbacks[id] && callbacks[id].isWatch) { post({ method: 'clearWatch', id: parseInt(id, 10) }); }
            }
        });
    })();
    """
}

/// Per-tab CoreLocation wrapper. Fans one CLLocationManager out to any number of
/// one-shot requests and watches (keyed by the JS request id).
final class WebGeolocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    private struct Subscriber {
        let highAccuracy: Bool
        let completion: (GeolocationEmission) -> Void
    }
    private var oneShots: [Int: Subscriber] = [:]
    private var watches: [Int: Subscriber] = [:]
    private var timeoutTimers: [Int: Timer] = [:]
    private var authWaiters: [(Bool) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
    }

    deinit {
        manager.stopUpdatingLocation()
        timeoutTimers.values.forEach { $0.invalidate() }
    }

    // MARK: Public API (main thread)

    func requestOneShot(id: Int, highAccuracy: Bool, timeout: Double?, maximumAge: Double,
                        completion: @escaping (GeolocationEmission) -> Void) {
        // maximumAge: serve a fresh-enough cached fix immediately.
        if maximumAge > 0, let location = lastLocation,
           Date().timeIntervalSince(location.timestamp) * 1000 <= maximumAge {
            completion(.make(from: location))
            return
        }
        withAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                completion(.error(code: 1, message: "User denied Geolocation"))
                return
            }
            self.oneShots[id] = Subscriber(highAccuracy: highAccuracy, completion: completion)
            if let timeout, timeout.isFinite {
                let timer = Timer.scheduledTimer(withTimeInterval: timeout / 1000, repeats: false) { [weak self] _ in
                    guard let self, let subscriber = self.oneShots.removeValue(forKey: id) else { return }
                    self.timeoutTimers.removeValue(forKey: id)?.invalidate()
                    subscriber.completion(.error(code: 3, message: "Timeout expired"))
                    self.updateServiceState()
                }
                self.timeoutTimers[id] = timer
            }
            self.updateServiceState()
        }
    }

    func startWatch(id: Int, highAccuracy: Bool, completion: @escaping (GeolocationEmission) -> Void) {
        withAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                completion(.error(code: 1, message: "User denied Geolocation"))
                return
            }
            self.watches[id] = Subscriber(highAccuracy: highAccuracy, completion: completion)
            // Deliver a cached fix right away if we have one (feels responsive).
            if let location = self.lastLocation { completion(.make(from: location)) }
            self.updateServiceState()
        }
    }

    func stopSubscription(id: Int) {
        oneShots.removeValue(forKey: id)
        watches.removeValue(forKey: id)
        timeoutTimers.removeValue(forKey: id)?.invalidate()
        updateServiceState()
    }

    // MARK: Authorization

    private func withAuthorization(_ completion: @escaping (Bool) -> Void) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            completion(true)
        case .notDetermined:
            authWaiters.append(completion)
            manager.requestWhenInUseAuthorization()
        default: // .denied, .restricted
            completion(false)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        let waiters = authWaiters
        authWaiters.removeAll()
        waiters.forEach { $0(granted) }
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location

        let shots = oneShots
        oneShots.removeAll()
        for (id, subscriber) in shots {
            timeoutTimers.removeValue(forKey: id)?.invalidate()
            subscriber.completion(.make(from: location))
        }
        for subscriber in watches.values {
            subscriber.completion(.make(from: location))
        }
        updateServiceState()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // locationUnknown is transient — keep trying / let the timeout handle it.
        if let clError = error as? CLError, clError.code == .locationUnknown { return }

        let code = (error as? CLError)?.code == .denied ? 1 : 2
        let shots = oneShots
        oneShots.removeAll()
        for (id, subscriber) in shots {
            timeoutTimers.removeValue(forKey: id)?.invalidate()
            subscriber.completion(.error(code: code, message: error.localizedDescription))
        }
        // W3C: report to watch error callbacks but keep the watch alive.
        for subscriber in watches.values {
            subscriber.completion(.error(code: code, message: error.localizedDescription))
        }
        updateServiceState()
    }

    // MARK: State

    private func updateServiceState() {
        if oneShots.isEmpty && watches.isEmpty {
            manager.stopUpdatingLocation()
            return
        }
        let wantsHighAccuracy = oneShots.values.contains { $0.highAccuracy }
            || watches.values.contains { $0.highAccuracy }
        manager.desiredAccuracy = wantsHighAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.startUpdatingLocation()
    }
}
