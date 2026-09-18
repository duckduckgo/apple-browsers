//
//  CPMMessagingDiagnosticsRecorder.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import Common
import Foundation
import os.log
import WebKit

/// Supplies the facts attached to CPM health pixels. Implemented by `CPMMessagingDiagnosticsRecorder`; mocked in tests.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public protocol CPMMessagingDiagnosticsProviding: AnyObject {
    /// Captures native state synchronously at the failed handshake, before the context or tab can change.
    func collectDiagnostics(tabIdentifier: String) -> CPMMessagingDiagnostics
}

/// Collects CPM lifecycle events and WebKit state for initialization-failure and stuck-messaging pixels.
/// Snapshots use native state without JavaScript probes.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class CPMMessagingDiagnosticsRecorder: CPMMessagingDiagnosticsProviding, CPMBackgroundWebViewProxyDelegate {

    /// Resolves a tab's web view and its optional WebKit extension-tab representation.
    public typealias TabResolver = @MainActor (_ tabIdentifier: String) -> (webView: WKWebView, extensionTab: (any WKWebExtensionTab)?)?
    /// Answers whether the app can currently route the context's `autoconsent` native messages. Set by `WebExtensionManager`.
    public typealias NativeMessageHandlerCheck = @MainActor (_ context: WKWebExtensionContext) -> Bool
    public var nativeMessageHandlerCheck: NativeMessageHandlerCheck?

    private enum SPISelector {
        static let networkProcessIdentifier = "_networkProcessIdentifier"
        static let webProcessIdentifier = "_webProcessIdentifier"
        /// `WKWebView._webProcessIsResponsive`: WebKit's own verdict from `ResponsivenessTimer` / `BackgroundProcessResponsivenessTimer`.
        static let webProcessIsResponsive = "_webProcessIsResponsive"
        /// `WKUserScript._contentWorld`.
        static let userScriptContentWorld = "_contentWorld"
    }

    /// One entry in the background lifecycle timeline attached to pixels as `bg_events`.
    struct BackgroundEvent: Equatable {
        enum Kind: Equatable {
            case contextLoad
            case viewCreated
            case viewDeallocated
            case processDied(CPMBackgroundProcessTerminationReason?)
            case unresponsive
            case responsive
            case contextError(String)
            case contextUnloadFailed(String)
            case extensionFilesRemoveFailed(String)
            case proxyInstalled
            case proxyRemoved
        }

        let kind: Kind
        let at: Date
    }

    /// Ordered background lifecycle events since `contextWillLoad` (oldest first), capped at `maximumRecordedEvents`.
    private(set) var backgroundEvents: [BackgroundEvent] = []
    static let maximumRecordedEvents = 40
    /// How many of the most recent events the pixel carries.
    static let maximumEventsInPixel = 12

    /// Whether WebKit currently considers the background process unresponsive (last `unresponsive` not yet followed by `responsive`).
    private(set) var backgroundProcessIsUnresponsive = false

    private let featureFlags: (any CPMDiagnosticsFeatureFlagsProviding)?
    private var featureFlagsCancellable: AnyCancellable?

    private let tabResolver: TabResolver
    private let now: () -> Date

    private weak var context: WKWebExtensionContext?
    private var contextGeneration = UUID()
    private var cpmContextIdentifier: String?
    private var contextErrorsObserver: NSObjectProtocol?
    private var recordedContextErrors: [String] = []
    private var networkProcessIdentifierAtLoad: Int32?

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private(set) var lastCriticalMemoryPressureAt: Date?

    private(set) var backgroundWebViewCreateCount = 0
    private weak var currentBackgroundWebView: WKWebView?
    /// Web process PID of the previous background view, to tell "view recreated after its process died" from "view recreated after idle eviction".
    private var previousBackgroundWebProcessIdentifier: Int32?
    private var networkProcessIdentifierAtLastBackgroundViewCreation: Int32?
    private var lastBackgroundWebViewCreatedAt: Date?
    /// Every background web view WebKit created for the CPM context that has not been deallocated yet.
    private var liveBackgroundWebViews: [WeakBox<WKWebView>] = []

    /// - Parameters:
    ///   - tabResolver: Maps the health monitor's tab identifier to the tab's web view. Platform-specific.
    ///   - observesMemoryPressure: Disable in tests to avoid installing a dispatch source.
    ///   - featureFlags: Delegate-proxy runtime switch; `nil` means observation is enabled.
    public init(tabResolver: @escaping TabResolver,
                observesMemoryPressure: Bool = true,
                featureFlags: (any CPMDiagnosticsFeatureFlagsProviding)? = nil,
                now: @escaping () -> Date = Date.init) {
        self.tabResolver = tabResolver
        self.featureFlags = featureFlags
        self.now = now
        if observesMemoryPressure {
            installMemoryPressureSource()
        }
        featureFlagsCancellable = featureFlags?.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeMainThread {
                    self?.applyFeatureFlags()
                }
            }
    }

    // MARK: - Feature flags

    var isBackgroundDelegateProxyEnabled: Bool {
        featureFlags?.isBackgroundDelegateProxyEnabled ?? true
    }

    /// Enables observation on the current view, or removes proxies from all surviving views when disabled.
    func applyFeatureFlags() {
        guard isBackgroundDelegateProxyEnabled else {
            pruneDeallocatedBackgroundWebViews()
            var removedProxy = false
            for webView in liveBackgroundWebViews.compactMap(\.value) where CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView) {
                CPMBackgroundWebViewDelegateProxy.uninstall(from: webView)
                removedProxy = true
            }
            if removedProxy {
                record(.proxyRemoved)
            }
            return
        }
        guard let webView = currentBackgroundWebView else { return }
        let installed = CPMBackgroundWebViewDelegateProxy.isInstalled(on: webView)
        if !installed {
            if CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: self) != nil {
                record(.proxyInstalled)
            }
        }
    }

    private func record(_ kind: BackgroundEvent.Kind) {
        if backgroundEvents.count >= Self.maximumRecordedEvents {
            backgroundEvents.removeFirst(backgroundEvents.count + 1 - Self.maximumRecordedEvents)
        }
        backgroundEvents.append(BackgroundEvent(kind: kind, at: now()))
    }

    // MARK: - Lifecycle facts

    /// Call right before `WKWebExtensionController.load(_:)` for the embedded extension context.
    public func contextWillLoad(_ context: WKWebExtensionContext) {
        if let contextErrorsObserver {
            NotificationCenter.default.removeObserver(contextErrorsObserver)
        }
        self.context = context
        contextGeneration = UUID()
        currentBackgroundWebView = nil
        let generation = contextGeneration
        cpmContextIdentifier = context.uniqueIdentifier
        recordedContextErrors = []
        backgroundWebViewCreateCount = 0
        previousBackgroundWebProcessIdentifier = nil
        networkProcessIdentifierAtLastBackgroundViewCreation = nil
        lastBackgroundWebViewCreatedAt = nil
        backgroundEvents = []
        backgroundProcessIsUnresponsive = false
        record(.contextLoad)
        networkProcessIdentifierAtLoad = Self.networkProcessIdentifier(for: context)
        Logger.webExtensions.info("[CPM Diagnostics] Context will load; networkProcessPID=\(self.networkProcessIdentifierAtLoad.map(String.init) ?? "unknown", privacy: .public)")

        contextErrorsObserver = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification,
            object: context,
            queue: .main
        ) { [weak self] notification in
            guard let context = notification.object as? WKWebExtensionContext else { return }
            MainActor.assumeMainThread {
                guard let self, self.context === context, self.contextGeneration == generation else { return }
                let errors = context.errors.map { $0 as NSError }
                for error in errors {
                    Logger.webExtensions.error("[CPM Diagnostics] Context error: \(error.domainAndCode, privacy: .public)")
                }
                self.recordContextErrors(errors)
            }
        }
    }

    public func contextUnloadFailed(identifier: String, error: Error) {
        guard identifier == cpmContextIdentifier else { return }
        record(.contextUnloadFailed((error as NSError).domainAndCode))
    }

    public func extensionFilesRemoveFailed(identifier: String, error: Error) {
        guard identifier == cpmContextIdentifier else { return }
        record(.extensionFilesRemoveFailed((error as NSError).domainAndCode))
    }

    /// Call after the embedded extension context was unloaded; a background web view still alive afterwards is a leak.
    public func contextDidUnload(identifier: String) {
        guard context == nil || context?.uniqueIdentifier == identifier else { return }
        if let contextErrorsObserver {
            NotificationCenter.default.removeObserver(contextErrorsObserver)
            self.contextErrorsObserver = nil
        }
        context = nil
        currentBackgroundWebView = nil
        pruneDeallocatedBackgroundWebViews()
        if !liveBackgroundWebViews.isEmpty {
            Logger.webExtensions.error("[CPM Diagnostics] \(self.liveBackgroundWebViews.count, privacy: .public) background web view(s) still alive after context unload")
        }
    }

    /// Call from `_webExtensionController:didCreateBackgroundWebView:forExtensionContext:`.
    public func didCreateBackgroundWebView(_ webView: WKWebView, for context: WKWebExtensionContext) {
        guard self.context === context else { return }
        backgroundWebViewCreateCount += 1

        // Facts about the view being replaced, captured before it is forgotten.
        let previousViewWasAlive = currentBackgroundWebView != nil
        let previousProcessIdentifier = previousBackgroundWebProcessIdentifier
        let previousProcessStillAlive = currentBackgroundWebView.flatMap(Self.webProcessIdentifier).map { $0 != 0 }
        let secondsSincePreviousCreation = lastBackgroundWebViewCreatedAt.map { now().timeIntervalSince($0) }
        let networkProcessIdentifierNow = Self.networkProcessIdentifier(for: context)
        let networkProcessChanged: Bool? = {
            guard let previous = networkProcessIdentifierAtLastBackgroundViewCreation, let networkProcessIdentifierNow else { return nil }
            return previous != networkProcessIdentifierNow
        }()

        currentBackgroundWebView = webView
        lastBackgroundWebViewCreatedAt = now()
        networkProcessIdentifierAtLastBackgroundViewCreation = networkProcessIdentifierNow
        backgroundProcessIsUnresponsive = false
        pruneDeallocatedBackgroundWebViews()
        liveBackgroundWebViews.append(WeakBox(webView))
        record(.viewCreated)

        // WebKit has just assigned its own navigation delegate (`WebExtensionContext::loadBackgroundWebView` sets it
        // before calling `didCreateBackgroundWebView`); wrap it to observe process termination and hang detection.
        if isBackgroundDelegateProxyEnabled,
           CPMBackgroundWebViewDelegateProxy.install(on: webView, delegate: self) != nil {
            record(.proxyInstalled)
        }
        let generation = contextGeneration
        webView.onDeinit { [weak self] in
            DispatchQueue.main.asyncOrNow {
                guard let self else { return }
                self.pruneDeallocatedBackgroundWebViews()
                guard self.contextGeneration == generation else { return }
                self.record(.viewDeallocated)
                Logger.webExtensions.debug("[CPM Diagnostics] Background web view deallocated")
            }
        }

        Logger.webExtensions.info("""
            [CPM Diagnostics] Background web view created #\(self.backgroundWebViewCreateCount, privacy: .public) \
            previousViewAlive=\(previousViewWasAlive, privacy: .public) \
            previousWebProcessPID=\(previousProcessIdentifier.map(String.init) ?? "none", privacy: .public) \
            previousWebProcessAlive=\(previousProcessStillAlive.map(String.init) ?? "unknown", privacy: .public) \
            secondsSincePreviousCreation=\(secondsSincePreviousCreation.map { String(Int($0)) } ?? "none", privacy: .public) \
            networkProcessPID=\(networkProcessIdentifierNow.map(String.init) ?? "unknown", privacy: .public) \
            networkProcessChangedSinceLastCreation=\(networkProcessChanged.map(String.init) ?? "unknown", privacy: .public)
            """)

        // WebKit delays the WebContent process launch until the first load (`delaysWebProcessLaunchUntilFirstLoad`,
        // default on macOS), so at this point the page has a dummy process and `_webProcessIdentifier` is 0. The real
        // PID appears only after the XPC launch completes (tens of ms, longer without a prewarmed process). Poll with
        // back-off until it is non-zero, so the next creation can compare against a real PID.
        previousBackgroundWebProcessIdentifier = nil
        sampleBackgroundWebProcessIdentifier(of: webView, creationIndex: backgroundWebViewCreateCount, attempt: 0)
    }

    private static let webProcessIdentifierSamplingDelays: [TimeInterval] = [0.1, 0.5, 1, 2, 5]

    private func sampleBackgroundWebProcessIdentifier(of webView: WKWebView, creationIndex: Int, attempt: Int) {
        guard attempt < Self.webProcessIdentifierSamplingDelays.count else {
            Logger.webExtensions.error("[CPM Diagnostics] Background web view #\(creationIndex, privacy: .public) webProcessPID still 0 after \(attempt, privacy: .public) samples")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.webProcessIdentifierSamplingDelays[attempt]) { [weak self, weak webView] in
            guard let self, let webView else { return }
            guard self.currentBackgroundWebView === webView else { return }
            let pid = Self.webProcessIdentifier(of: webView)
            if let pid, pid != 0 {
                self.previousBackgroundWebProcessIdentifier = pid
                Logger.webExtensions.info("[CPM Diagnostics] Background web view #\(creationIndex, privacy: .public) webProcessPID=\(pid, privacy: .public)")
            } else if pid == nil {
                Logger.webExtensions.info("[CPM Diagnostics] Background web view #\(creationIndex, privacy: .public) webProcessPID=unknown (SPI unavailable)")
            } else {
                self.sampleBackgroundWebProcessIdentifier(of: webView, creationIndex: creationIndex, attempt: attempt + 1)
            }
        }
    }

    /// Current background WebContent PID, re-sampled on demand (`0` = no running process, `nil` = SPI unavailable or no view).
    public var currentBackgroundWebProcessIdentifier: Int32? {
        guard let currentBackgroundWebView else { return nil }
        let pid = Self.webProcessIdentifier(of: currentBackgroundWebView)
        if let pid, pid != 0 {
            previousBackgroundWebProcessIdentifier = pid
        }
        return pid
    }

    // MARK: - CPMMessagingDiagnosticsProviding

    public func collectDiagnostics(tabIdentifier: String) -> CPMMessagingDiagnostics {
        var diagnostics = snapshot()
        let resolvedTab = tabResolver(tabIdentifier)

        if let context, let resolvedTab, let extensionTab = resolvedTab.extensionTab {
            diagnostics.tabKnownToWebKit = context.openTabs.contains { ($0.base as AnyObject) === (extensionTab as AnyObject) }
        }

        if let context, let resolvedTab {
            let tabController = resolvedTab.webView.configuration.webExtensionController
            diagnostics.tabControllerMatchesContext = tabController != nil && tabController === context.webExtensionController
            // `WKUserScript` exposes its world only through the `_contentWorld` SPI (WKUserScriptPrivate.h, macOS 11+).
            let extensionWorldName = Self.contentScriptWorldName(for: context)
            let userScripts = resolvedTab.webView.configuration.userContentController.userScripts
            if userScripts.allSatisfy({ $0.responds(to: NSSelectorFromString(SPISelector.userScriptContentWorld)) }) {
                diagnostics.tabHasExtensionUserScripts = userScripts.contains {
                    ($0.value(forKey: SPISelector.userScriptContentWorld) as? WKContentWorld)?.name == extensionWorldName
                }
            }
        }

        return diagnostics
    }

    /// Synchronous facts only; safe to call from a breakage report.
    public func snapshot() -> CPMMessagingDiagnostics {
        pruneDeallocatedBackgroundWebViews()
        var diagnostics = CPMMessagingDiagnostics()
        diagnostics.extensionContextLoaded = context?.isLoaded ?? false
        diagnostics.secondsSinceCriticalMemoryPressure = lastCriticalMemoryPressureAt.map { now().timeIntervalSince($0) }
        diagnostics.extensionContextErrors = currentContextErrors()
        diagnostics.backgroundWebViewCreateCount = backgroundWebViewCreateCount
        diagnostics.backgroundWebViewAlive = currentBackgroundWebView != nil
        diagnostics.leakedBackgroundWebViewCount = leakedBackgroundWebViewCount()
        if let context, let nativeMessageHandlerCheck {
            diagnostics.nativeMessageHandlerRegistered = nativeMessageHandlerCheck(context)
        }
        if let context, let identifierAtLoad = networkProcessIdentifierAtLoad,
           let identifierNow = Self.networkProcessIdentifier(for: context) {
            diagnostics.networkProcessRestarted = identifierAtLoad != identifierNow
        }
        if let backgroundWebView = currentBackgroundWebView {
            diagnostics.backgroundWebProcessAlive = Self.webProcessIdentifier(of: backgroundWebView).map { $0 != 0 }
            diagnostics.backgroundWebProcessResponsive = Self.webProcessIsResponsive(backgroundWebView)
        }
        let snapshotTime = now()
        diagnostics.backgroundEvents = backgroundEvents.suffix(Self.maximumEventsInPixel).map {
            CPMMessagingDiagnostics.BackgroundEvent(token: $0.kind.description, secondsBeforeSnapshot: snapshotTime.timeIntervalSince($0.at))
        }
        return diagnostics
    }

    // MARK: - CPMBackgroundWebViewProxyDelegate

    public func backgroundWebView(_ webView: WKWebView, webContentProcessDidTerminateWith reason: CPMBackgroundProcessTerminationReason?) {
        guard webView === currentBackgroundWebView else { return }
        backgroundProcessIsUnresponsive = false
        record(.processDied(reason))
        Logger.webExtensions.error("""
            [CPM Diagnostics] Background WebContent process #\(self.backgroundWebViewCreateCount, privacy: .public) died: \
            reason=\(reason?.description ?? "unknown", privacy: .public) pid=\(self.previousBackgroundWebProcessIdentifier.map(String.init) ?? "unknown", privacy: .public)
            """)
    }

    public func backgroundWebViewWebProcessDidBecomeUnresponsive(_ webView: WKWebView) {
        guard webView === currentBackgroundWebView else { return }
        backgroundProcessIsUnresponsive = true
        record(.unresponsive)
    }

    public func backgroundWebViewWebProcessDidBecomeResponsive(_ webView: WKWebView) {
        guard webView === currentBackgroundWebView else { return }
        backgroundProcessIsUnresponsive = false
        record(.responsive)
    }

    /// Name of the isolated world WebKit injects the context's content scripts into (`WebExtensionContext::load`).
    public static func contentScriptWorldName(for context: WKWebExtensionContext) -> String {
        "WebExtension-\(context.uniqueIdentifier)"
    }

    // MARK: - Testing

    func recordCriticalMemoryPressureForTesting() {
        lastCriticalMemoryPressureAt = now()
    }

    // MARK: - Private

    private func installMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncOrNow {
                guard let self, self.memoryPressureSource?.data.contains(.critical) == true else { return }
                self.lastCriticalMemoryPressureAt = self.now()
                Logger.webExtensions.warning("[CPM Diagnostics] Critical memory pressure observed")
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func recordContextErrors(_ errors: [NSError]) {
        for domainAndCode in errors.map(\.domainAndCode) where !recordedContextErrors.contains(domainAndCode) {
            recordedContextErrors.append(domainAndCode)
        }
        // Suppress identical consecutive background-load errors reported within one second.
        // This does not distinguish new failures from repeated error-list notifications.
        for error in errors where error.domain == WKWebExtensionContext.errorDomain
            && error.code == WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue {
            let domainAndCode = error.domainAndCode
            if backgroundEvents.last.map({ $0.kind == .contextError(domainAndCode) && now().timeIntervalSince($0.at) < 1 }) != true {
                record(.contextError(domainAndCode))
            }
        }
    }

    private func currentContextErrors() -> [String] {
        var errors = recordedContextErrors
        for domainAndCode in (context?.errors ?? []).map({ ($0 as NSError).domainAndCode }) where !errors.contains(domainAndCode) {
            errors.append(domainAndCode)
        }
        return errors
    }

    private func pruneDeallocatedBackgroundWebViews() {
        liveBackgroundWebViews.removeAll { $0.value == nil }
    }

    private func leakedBackgroundWebViewCount() -> Int {
        let expectedLive = (context != nil && currentBackgroundWebView != nil) ? 1 : 0
        return max(0, liveBackgroundWebViews.count - expectedLive)
    }

    /// `WKWebsiteDataStore._networkProcessIdentifier`, or `nil` when the SPI is unavailable.
    private static func networkProcessIdentifier(for context: WKWebExtensionContext) -> Int32? {
        let dataStore = context.webViewConfiguration?.websiteDataStore ?? .default()
        guard dataStore.responds(to: NSSelectorFromString(SPISelector.networkProcessIdentifier)) else { return nil }
        return (dataStore.value(forKey: SPISelector.networkProcessIdentifier) as? NSNumber)?.int32Value
    }

    /// `WKWebView._webProcessIdentifier`, or `nil` when the SPI is unavailable. `0` means no web content process.
    private static func webProcessIdentifier(of webView: WKWebView) -> Int32? {
        guard webView.responds(to: NSSelectorFromString(SPISelector.webProcessIdentifier)) else { return nil }
        return (webView.value(forKey: SPISelector.webProcessIdentifier) as? NSNumber)?.int32Value
    }

    /// `WKWebView._webProcessIsResponsive`, or `nil` when the SPI is unavailable.
    private static func webProcessIsResponsive(_ webView: WKWebView) -> Bool? {
        guard webView.responds(to: NSSelectorFromString(SPISelector.webProcessIsResponsive)) else { return nil }
        return (webView.value(forKey: SPISelector.webProcessIsResponsive) as? NSNumber)?.boolValue
    }

}

@available(macOS 15.4, iOS 18.4, *)
extension CPMMessagingDiagnosticsRecorder.BackgroundEvent.Kind: CustomStringConvertible {

    var description: String {
        switch self {
        case .contextLoad: return "load"
        case .viewCreated: return "view"
        case .viewDeallocated: return "dealloc"
        case .processDied(let reason): return "died_\(reason?.description ?? "unknown")"
        case .unresponsive: return "unresponsive"
        case .responsive: return "responsive"
        case .contextError(let descriptor): return "error_\(descriptor)"
        case .contextUnloadFailed(let descriptor): return "context_unload_failed_\(descriptor)"
        case .extensionFilesRemoveFailed(let descriptor): return "extension_files_remove_failed_\(descriptor)"
        case .proxyInstalled: return "proxy_on"
        case .proxyRemoved: return "proxy_off"
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private extension NSError {

    /// `domain:code`, followed by the immediate underlying domain/code; excludes error text.
    var domainAndCode: String {
        var descriptor = "\(domain):\(code)"
        if let underlying = userInfo[NSUnderlyingErrorKey] as? NSError {
            descriptor += ":\(underlying.domain):\(underlying.code)"
        }
        return descriptor
    }

}

private struct WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
