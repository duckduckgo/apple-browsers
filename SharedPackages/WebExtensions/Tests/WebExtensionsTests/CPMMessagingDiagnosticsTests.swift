//
//  CPMMessagingDiagnosticsTests.swift
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

import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingDiagnosticsTests: XCTestCase {

    typealias Name = CPMMessagingDiagnostics.ParameterName

    func testEmptyDiagnosticsOnlyCarryDefaults() {
        let parameters = CPMMessagingDiagnostics().pixelParameters

        XCTAssertEqual(parameters, [
            Name.memoryPressureCritical: "none",
            Name.extensionContextErrors: "none"
        ])
    }

    func testWhenRecorderIsRecreatedThenAppLaunchAgeDoesNotReset() {
        var date = Date(timeIntervalSince1970: 1000)
        let session = CPMAppSessionDiagnostics(appVersionChange: nil, launchDate: date)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date }, appSession: session)
        XCTAssertEqual(recorder.snapshot().pixelParameters["app_launch_age"], "30s")
        date += 60
        let replacement = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date }, appSession: session)
        XCTAssertEqual(recorder.snapshot().pixelParameters["app_launch_age"], "2m")
        XCTAssertEqual(replacement.snapshot().pixelParameters["app_launch_age"], "2m")
        XCTAssertNil(replacement.snapshot().pixelParameters["app_version_change"])
    }

    func testWhenAppWasUpdatedThenSnapshotIncludesOnlyVersionChangeAndBucket() {
        let date = Date(timeIntervalSince1970: 1000)
        let session = CPMAppSessionDiagnostics(appVersionChange: .updated, launchDate: date)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date }, appSession: session)
        XCTAssertEqual(recorder.snapshot().pixelParameters["app_version_change"], "updated")
        XCTAssertEqual(recorder.snapshot().pixelParameters["app_launch_age"], "30s")
    }

    func testWhenParameterNamesAreSerializedThenUsesCompactKeys() {
        XCTAssertEqual([
            Name.extensionContextLoaded, Name.memoryPressureCritical, Name.networkProcessRestarted,
            Name.extensionContextErrors, Name.backgroundViewCreateCount, Name.backgroundViewAlive,
            Name.backgroundViewLeakedCount, Name.backgroundWebProcessAlive, Name.tabKnownToWebKit,
            Name.nativeMessageHandlerRegistered, Name.tabControllerMatchesContext, Name.tabHasExtensionUserScripts,
            Name.backgroundWebProcessResponsive, Name.backgroundGraveyardTreatmentEnabled, Name.backgroundEvents
        ], [
            "context_loaded", "critical_memory_age", "network_restarted",
            "context_errors", "bg_view_creations", "bg_view_alive",
            "bg_view_leaked_count", "bg_process_alive", "tab_in_context",
            "handler_registered", "tab_controller_match", "tab_has_ext_scripts",
            "bg_process_responsive", "background_graveyard_enabled", "bg_events"
        ])
    }

    func testBackgroundEventsDropOldestEntriesToFitTheCap() {
        let events = (0..<40).map {
            CPMMessagingDiagnostics.BackgroundEvent(token: "error_background_failed_to_load_\($0)", secondsBeforeSnapshot: TimeInterval(39 - $0))
        }
        let value = CPMMessagingDiagnostics.backgroundEventsValue(events)

        XCTAssertLessThanOrEqual(value.count, CPMMessagingDiagnostics.maximumBackgroundEventsLength)
        XCTAssertTrue(value.hasSuffix("error_background_failed_to_load_39@30s"), "newest event must survive")
        XCTAssertFalse(value.contains("error_background_failed_to_load_0@"), "oldest events are dropped first")
    }

    func testBackgroundEventTokensAreSanitized() {
        let value = CPMMessagingDiagnostics.backgroundEventsValue([
            .init(token: "Died Crash; https://example.com/?q=1", secondsBeforeSnapshot: -3)
        ])
        XCTAssertEqual(value, "diedcrashhttps:examplecomq1@30s")
    }

    func testWhenBackgroundEventAgeCrossesBoundaryThenUsesNextBucket() {
        let cases: [(TimeInterval, String)] = [
            (-1, "30s"), (0, "30s"), (29.999, "30s"),
            (30, "1m"), (59.999, "1m"),
            (60, "2m"), (119.999, "2m"),
            (120, "5m"), (299.999, "5m"),
            (300, "15m"), (899.999, "15m"),
            (900, "over_15"), (86_400, "over_15")
        ]
        for (seconds, bucket) in cases {
            let value = CPMMessagingDiagnostics.backgroundEventsValue([.init(token: "view", secondsBeforeSnapshot: seconds)])
            XCTAssertEqual(value, "view@\(bucket)", "age: \(seconds)")
        }
    }

    func testWhenBackgroundEventsShareBucketThenPreservesOrderAndDuplicates() {
        let value = CPMMessagingDiagnostics.backgroundEventsValue([
            .init(token: "view", secondsBeforeSnapshot: 29),
            .init(token: "died_crash", secondsBeforeSnapshot: 20),
            .init(token: "view", secondsBeforeSnapshot: 10)
        ])
        XCTAssertEqual(value, "view@30s,died_crash@30s,view@30s")
    }

    func testMemoryPressureIsBucketed() {
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(nil), "none")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(0), "1m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(59.9), "1m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(60), "5m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(299), "5m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(300), "30m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(1800), "over_30")
    }

    func testCountsAreBucketed() {
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(0), "0")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(1), "1")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(2), "2")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(3), "3_to_5")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(5), "3_to_5")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(6), "over_5")
    }

    func testBackgroundReadinessIsBucketedAroundTheGracePeriodAndTheUnloadTimer() {
        let values = [
            CPMBackgroundReadiness.noBackground, .pending, .failed,
            .loaded(secondsAfterViewCreation: 0.9), .loaded(secondsAfterViewCreation: 1),
            .loaded(secondsAfterViewCreation: 4), .loaded(secondsAfterViewCreation: 10), .loaded(secondsAfterViewCreation: 30)
        ].map(CPMMessagingDiagnostics.readinessValue)
        XCTAssertEqual(values, ["none", "pending", "failed", "under_1s", "1s_to_4s", "4s_to_10s", "10s_to_30s", "over_30s"])
    }

    func testBackgroundViewAgeIsBucketedFinerThanTheEventTimeline() {
        let buckets = [0, 3.9, 4, 7.9, 8, 29.9, 30, 119.9, 120].map(CPMMessagingDiagnostics.backgroundViewAgeBucket)
        XCTAssertEqual(buckets, ["under_4s", "under_4s", "4s_to_8s", "4s_to_8s", "8s_to_30s", "8s_to_30s", "30s_to_2m", "30s_to_2m", "over_2m"])
    }

    func testOpenTabCountsAreBucketed() {
        let buckets = [0, 1, 2, 5, 6, 10, 11, 20, 21, 50, 51].map(CPMMessagingDiagnostics.tabCountBucket)
        XCTAssertEqual(buckets, ["0", "1", "2_to_5", "2_to_5", "6_to_10", "6_to_10", "11_to_20", "11_to_20", "21_to_50", "21_to_50", "over_50"])
    }

    func testFullDiagnosticsRenderEveryParameter() {
        var diagnostics = CPMMessagingDiagnostics()
        diagnostics.extensionContextLoaded = true
        diagnostics.secondsSinceCriticalMemoryPressure = 30
        diagnostics.networkProcessRestarted = true
        diagnostics.extensionContextErrors = ["background_failed_to_load:NSURLErrorDomain:-1100"]
        diagnostics.backgroundWebViewCreateCount = 4
        diagnostics.backgroundWebViewAlive = true
        diagnostics.leakedBackgroundWebViewCount = 1
        diagnostics.backgroundWebProcessAlive = false
        diagnostics.tabKnownToWebKit = false
        diagnostics.nativeMessageHandlerRegistered = false
        diagnostics.tabControllerMatchesContext = false
        diagnostics.tabHasExtensionUserScripts = false
        diagnostics.backgroundWebProcessResponsive = false
        diagnostics.backgroundGraveyardTreatmentEnabled = true
        diagnostics.hasBackgroundLoadError = true
        diagnostics.backgroundLoadErrorAppState = .background
        diagnostics.secondsFromBackgroundViewToLoadError = 30.2
        diagnostics.applicationState = .inactive
        diagnostics.secondsSinceBackgroundViewCreation = 5
        diagnostics.backgroundReadiness = .loaded(secondsAfterViewCreation: 4.5)
        diagnostics.openTabCount = 12
        diagnostics.loadingTabCount = 3
        diagnostics.backgroundEvents = [
            .init(token: "load", secondsBeforeSnapshot: 600.4),
            .init(token: "view", secondsBeforeSnapshot: 599),
            .init(token: "died_crash", secondsBeforeSnapshot: 42),
            .init(token: "error_background_failed_to_load:NSURLErrorDomain:-1100", secondsBeforeSnapshot: 41.6),
        ]

        XCTAssertEqual(diagnostics.pixelParameters, [
            Name.backgroundWebProcessResponsive: "false",
            Name.backgroundGraveyardTreatmentEnabled: "true",
            Name.backgroundLoadErrorAppState: "background",
            Name.backgroundLoadErrorAfter: "25s_to_35s",
            Name.applicationState: "inactive",
            Name.backgroundViewAge: "4s_to_8s",
            Name.backgroundReadyAfter: "4s_to_10s",
            Name.openTabs: "11_to_20",
            Name.loadingTabs: "3_to_5",
            Name.backgroundEvents: "load@15m,view@15m,died_crash@1m,error_background_failed_to_load:nsurlerrordomain:-1100@1m",
            Name.extensionContextLoaded: "true",
            Name.memoryPressureCritical: "1m",
            Name.networkProcessRestarted: "true",
            Name.extensionContextErrors: "background_failed_to_load:NSURLErrorDomain:-1100",
            Name.backgroundViewCreateCount: "3_to_5",
            Name.backgroundViewAlive: "true",
            Name.backgroundViewLeakedCount: "1",
            Name.backgroundWebProcessAlive: "false",
            Name.tabKnownToWebKit: "false",
            Name.nativeMessageHandlerRegistered: "false",
            Name.tabControllerMatchesContext: "false",
            Name.tabHasExtensionUserScripts: "false"
        ])
    }

}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingDiagnosticsRecorderTests: XCTestCase {

    private var createdTestExtensionDirs: [URL] = []

    func testWhenContextReloadsThenSessionEventsKeepTheirOriginalAges() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let session = CPMAppSessionDiagnostics(appVersionChange: nil, launchDate: date)
        date += 60
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false,
                                                      now: { date }, appSession: session)
        recorder.extensionDidUpdate(type: .embedded)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().pixelParameters["bg_events"], "extension_updated@30s,load@30s")
        XCTAssertEqual(recorder.snapshot().pixelParameters["app_launch_age"], "2m")

        date += 60
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().pixelParameters["bg_events"], "extension_updated@2m,load@30s")
        XCTAssertEqual(recorder.snapshot().pixelParameters["app_launch_age"], "5m")
    }

    func testWhenOtherExtensionUpdatesOrCPMReloadsThenNoUpdateEventIsAdded() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        recorder.extensionDidUpdate(type: .adBlockingExtension)
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        recorder.extensionDidUpdate(type: .embedded)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load", "extension_updated"])
    }

    func testWhenBaseURLChangesAcrossUnloadThenRecordsChangeWithoutURL() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false,
                                                      now: { Date(timeIntervalSince1970: 1000) })
        let context = try await makeContext()
        context.baseURL = try XCTUnwrap(URL(string: "webkit-extension://first/"))
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        recorder.contextDidUnload(identifier: context.uniqueIdentifier)

        let replacement = try await makeContext()
        replacement.baseURL = try XCTUnwrap(URL(string: "webkit-extension://second/"))
        recorder.contextWillLoad(replacement)
        XCTAssertEqual(recorder.snapshot().pixelParameters["bg_events"], "load@30s,base_url_changed@30s")

        recorder.contextWillLoad(replacement)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
    }

    func testWhenContextIdentifierChangesThenDoesNotCompareBaseURLs() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        context.baseURL = try XCTUnwrap(URL(string: "webkit-extension://first/"))
        recorder.contextWillLoad(context)

        let replacement = try await makeContext()
        replacement.uniqueIdentifier = "another-extension"
        replacement.baseURL = try XCTUnwrap(URL(string: "webkit-extension://second/"))
        recorder.contextWillLoad(replacement)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
    }

    func testWhenBackgroundLoadFailsThenAppStateAndDelayFromViewCreationAreReported() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let session = CPMAppSessionDiagnostics(appVersionChange: nil, launchDate: date) { .background }
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil },
                                                       observesMemoryPressure: false,
                                                       now: { date },
                                                       appSession: session)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().pixelParameters[CPMMessagingDiagnostics.ParameterName.backgroundLoadErrorAppState], "none")
        XCTAssertEqual(recorder.snapshot().pixelParameters[CPMMessagingDiagnostics.ParameterName.backgroundLoadErrorAfter], "none")

        recorder.didCreateBackgroundWebView(WKWebView(frame: .zero), for: context)
        date += 30.4
        recorder.recordContextErrors([NSError(domain: WKWebExtensionContext.errorDomain,
                                              code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue)])

        let parameters = recorder.snapshot().pixelParameters
        XCTAssertEqual(parameters[CPMMessagingDiagnostics.ParameterName.backgroundLoadErrorAppState], "background")
        XCTAssertEqual(parameters[CPMMessagingDiagnostics.ParameterName.backgroundLoadErrorAfter], "25s_to_35s")

        recorder.contextWillLoad(try await makeContext())
        XCTAssertEqual(recorder.snapshot().pixelParameters[CPMMessagingDiagnostics.ParameterName.backgroundLoadErrorAfter], "none", "a new context starts clean")
    }

    func testBackgroundReadinessFollowsTheLoadOfTheCurrentView() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date })
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.loadBackgroundContent = { _, completion in completions.append(completion) }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.backgroundReadyAfter], "none")
        XCTAssertNil(recorder.snapshot().pixelParameters[Name.backgroundViewAge])

        let webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.backgroundReadyAfter], "pending")
        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.backgroundViewAge], "under_4s")

        await nextMainQueueTurn()
        XCTAssertEqual(completions.count, 1, "the load is requested on the next turn, not from inside WebKit's callback")
        date += 5.2
        completions[0](nil)
        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.backgroundReadyAfter], "4s_to_10s")
        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.backgroundViewAge], "4s_to_8s")
    }

    func testFailedBackgroundLoadIsReportedAsFailed() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.loadBackgroundContent = { _, completion in completions.append(completion) }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        await nextMainQueueTurn()

        completions.first?(NSError(domain: WKWebExtensionContext.errorDomain,
                                   code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue))

        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.backgroundReadyAfter], "failed")
    }

    func testLoadOfAReplacedBackgroundViewDoesNotMarkTheNewOneReady() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.loadBackgroundContent = { _, completion in completions.append(completion) }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let firstView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(firstView, for: context)
        await nextMainQueueTurn()
        let secondView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(secondView, for: context)

        completions.first?(nil)

        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.backgroundReadyAfter], "pending")
    }

    func testReadinessIsOmittedWhenBackgroundObservationIsDisabled() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: false)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, featureFlags: flags)
        var loadRequests = 0
        recorder.backgroundReadinessObserver.loadBackgroundContent = { _, _ in loadRequests += 1 }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        XCTAssertNil(recorder.snapshot().pixelParameters[Name.backgroundReadyAfter])

        let webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        await nextMainQueueTurn()

        XCTAssertNil(recorder.snapshot().pixelParameters[Name.backgroundReadyAfter])
        XCTAssertEqual(loadRequests, 0)
    }

    func testAppStateIsReportedWithEverySnapshot() {
        let session = CPMAppSessionDiagnostics(appVersionChange: nil, launchDate: Date()) { .inactive }
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, appSession: session)

        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.applicationState], "inactive")
    }

    func testOpenAndLoadingTabsAreCounted() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        try controller.load(context)
        defer { try? controller.unload(context) }
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().pixelParameters[Name.openTabs], "0")

        let schemeHandler = NeverRespondingSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "cpm-test")
        let loadingView = WKWebView(frame: .zero, configuration: configuration)
        loadingView.load(URLRequest(url: try XCTUnwrap(URL(string: "cpm-test://page"))))
        let tabs = [TestTab(webView: loadingView), TestTab(webView: WKWebView(frame: .zero)), TestTab(webView: nil)]
        tabs.forEach { controller.didOpenTab($0) }
        let started = expectation(description: "page load started")
        schemeHandler.onStart = { started.fulfill() }
        await fulfillment(of: [started], timeout: 5)

        // WebKit holds tabs weakly, and an optimized build releases `tabs` after its last use.
        let parameters = withExtendedLifetime(tabs) { recorder.snapshot().pixelParameters }
        XCTAssertEqual(parameters[Name.openTabs], "2_to_5")
        XCTAssertEqual(parameters[Name.loadingTabs], "1")
    }

    /// A snapshot is taken while CPM is failing, so it must only read: the apps' tabs return a stored web
    /// view from `webView(for:)`, and anything else the recorder asked a tab for could create state or
    /// work in the middle of a failure. Anything WebKit itself asks for when listing `openTabs` is not ours.
    func testSnapshotOnlyReadsTheWebViewOfEachOpenTab() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        try controller.load(context)
        defer { try? controller.unload(context) }
        recorder.contextWillLoad(context)
        let tabs = [RecordingTab(webView: WKWebView(frame: .zero)), RecordingTab(webView: nil)]
        tabs.forEach { controller.didOpenTab($0) }
        XCTAssertEqual(context.openTabs.count, tabs.count, "the tabs must be registered, or nothing below is exercised")

        tabs.forEach { $0.forgetCalls() }
        _ = context.openTabs
        let callsListingOpenTabs = tabs.map(\.calls)

        tabs.forEach { $0.forgetCalls() }
        let first = recorder.snapshot().pixelParameters
        let callsDuringFirstSnapshot = tabs.map(\.calls)
        tabs.forEach { $0.forgetCalls() }
        _ = recorder.snapshot()
        let callsDuringSecondSnapshot = tabs.map(\.calls)
        withExtendedLifetime(tabs) {}

        let expected = callsListingOpenTabs.map { $0 + ["webView"] }
        XCTAssertEqual(callsDuringFirstSnapshot, expected, "a snapshot may only read each tab's web view, once")
        XCTAssertEqual(callsDuringSecondSnapshot, expected, "a repeated snapshot must not do more than the first")
        XCTAssertEqual(first[Name.openTabs], "2_to_5")
        XCTAssertEqual(first[Name.loadingTabs], "0", "a tab without a web view is open but not loading")
    }

    private typealias Name = CPMMessagingDiagnostics.ParameterName

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testLoadErrorDelayIsBucketedAroundTheBackgroundUnloadTimer() {
        XCTAssertEqual(CPMMessagingDiagnostics.loadErrorDelayBucket(0.5), "under_5s")
        XCTAssertEqual(CPMMessagingDiagnostics.loadErrorDelayBucket(5), "5s_to_25s")
        XCTAssertEqual(CPMMessagingDiagnostics.loadErrorDelayBucket(25), "25s_to_35s")
        XCTAssertEqual(CPMMessagingDiagnostics.loadErrorDelayBucket(34.9), "25s_to_35s")
        XCTAssertEqual(CPMMessagingDiagnostics.loadErrorDelayBucket(35), "over_35s")
    }

    func testWhenContextErrorIsRecordedThenDescriptorCarriesCodesNotText() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: [NSLocalizedDescriptionKey: "/Users/someone/file.js"])
        let error = NSError(domain: WKWebExtensionContext.errorDomain,
                            code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue,
                            userInfo: [NSUnderlyingErrorKey: underlying, NSLocalizedDescriptionKey: "The background content failed to load."])

        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: error)
        let descriptor = try XCTUnwrap(recorder.snapshot().backgroundEvents.last?.token)

        XCTAssertEqual(descriptor, "context_unload_failed_\(error.domain):\(error.code):\(NSURLErrorDomain):\(NSURLErrorFileDoesNotExist)")
        XCTAssertFalse(descriptor.contains("/Users"))
        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: NSError(domain: "Custom", code: 7))
        XCTAssertEqual(recorder.snapshot().backgroundEvents.last?.token, "context_unload_failed_Custom:7")
        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier,
                                     error: NSError(domain: WKWebExtensionContext.errorDomain, code: 999))
        XCTAssertEqual(recorder.snapshot().backgroundEvents.last?.token, "context_unload_failed_\(WKWebExtensionContext.errorDomain):999")
    }

    override func tearDown() {
        for dir in createdTestExtensionDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        createdTestExtensionDirs.removeAll()
        super.tearDown()
    }

    func testBackgroundWebViewCreationAndDeallocationAreRecorded() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()

        recorder.contextWillLoad(context)
        var snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundWebViewCreateCount, 0)
        XCTAssertEqual(snapshot.backgroundWebViewAlive, false)
        XCTAssertEqual(snapshot.leakedBackgroundWebViewCount, 0)

        var webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundWebViewCreateCount, 1)
        XCTAssertEqual(snapshot.backgroundWebViewAlive, true)
        XCTAssertEqual(snapshot.leakedBackgroundWebViewCount, 0)

        // WebKit replaces the background view: the old one is retained here to simulate a leak.
        let retainedOldView = webView
        webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        withExtendedLifetime((retainedOldView, webView)) {
            snapshot = recorder.snapshot()
            XCTAssertEqual(snapshot.backgroundWebViewCreateCount, 2)
            XCTAssertEqual(snapshot.leakedBackgroundWebViewCount, 1)

            // Once the context is gone, the current view counts as leaked too until it deallocates.
            recorder.contextDidUnload(identifier: context.uniqueIdentifier)
            XCTAssertEqual(recorder.snapshot().leakedBackgroundWebViewCount, 2)
            XCTAssertEqual(recorder.snapshot().extensionContextLoaded, false)
        }
    }

    func testCollectDiagnosticsWithoutTabLeavesTabFactsUnknown() async {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)

        let diagnostics = recorder.collectDiagnostics(tabIdentifier: "missing")

        XCTAssertNil(diagnostics.tabKnownToWebKit)
    }

    func testMemoryPressureIsReportedRelativeToNow() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { currentDate })

        XCTAssertNil(recorder.snapshot().secondsSinceCriticalMemoryPressure)

        recorder.recordCriticalMemoryPressureForTesting()
        currentDate = currentDate.addingTimeInterval(90)

        XCTAssertEqual(recorder.snapshot().secondsSinceCriticalMemoryPressure, 90)
    }

    func testUnloadFailurePreservesCPMContextAndBackgroundView() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        let webView = WKWebView(frame: .zero)
        recorder.contextWillLoad(context)
        recorder.didCreateBackgroundWebView(webView, for: context)
        recorder.nativeMessageHandlerCheck = { $0 === context }

        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: NSError(domain: "UnloadError", code: 7))

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundWebViewAlive, true)
        XCTAssertEqual(snapshot.nativeMessageHandlerRegistered, true)
        XCTAssertEqual(snapshot.backgroundEvents.last?.token, "context_unload_failed_UnloadError:7")
    }

    func testFileRemovalFailureIsRecordedAfterSuccessfulUnloadWithoutErrorText() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        recorder.contextDidUnload(identifier: context.uniqueIdentifier)
        let error = NSError(domain: "FilesError", code: 13,
                            userInfo: [NSLocalizedDescriptionKey: "https://private.example", NSFilePathErrorKey: "/Users/private"])

        recorder.extensionFilesRemoveFailed(identifier: context.uniqueIdentifier, error: error)

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundEvents.last?.token, "extension_files_remove_failed_FilesError:13")
        XCTAssertEqual(snapshot.extensionContextLoaded, false)
        let payload = snapshot.pixelParameters.values.joined()
        XCTAssertFalse(payload.contains("private"))
    }

    func testLifecycleFailuresIgnoreOtherExtensionsAndPreviousContext() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let error = NSError(domain: "TestError", code: 1)
        recorder.contextUnloadFailed(identifier: "another-extension", error: error)
        recorder.extensionFilesRemoveFailed(identifier: "another-extension", error: error)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])

        let replacement = try await makeContext()
        replacement.uniqueIdentifier = "replacement"
        recorder.contextWillLoad(replacement)
        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: error)
        recorder.extensionFilesRemoveFailed(identifier: context.uniqueIdentifier, error: error)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
    }

    func testWhenOldViewCallsBackAfterContextReplacementThenNewTimelineIsUnchanged() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let oldContext = try await makeContext()
        let replacement = try await makeContext()
        let oldView = WKWebView(frame: .zero)
        replacement.baseURL = oldContext.baseURL
        recorder.contextWillLoad(oldContext)
        recorder.didCreateBackgroundWebView(oldView, for: oldContext)

        recorder.contextWillLoad(replacement)
        recorder.backgroundWebView(oldView, webContentProcessDidTerminateWith: .crash)
        recorder.backgroundWebViewWebProcessDidBecomeUnresponsive(oldView)
        recorder.backgroundWebViewWebProcessDidBecomeResponsive(oldView)
        recorder.didCreateBackgroundWebView(oldView, for: oldContext)

        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        XCTAssertEqual(recorder.snapshot().backgroundWebViewAlive, false)
        XCTAssertEqual(recorder.snapshot().backgroundWebViewCreateCount, 0)
    }

    func testWhenOldViewDeallocatesAfterContextReplacementThenNewTimelineIsUnchanged() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let oldContext = try await makeContext()
        let replacement = try await makeContext()
        weak var releasedView: WKWebView?
        replacement.baseURL = oldContext.baseURL
        autoreleasepool {
            let view = WKWebView(frame: .zero)
            releasedView = view
            recorder.contextWillLoad(oldContext)
            recorder.didCreateBackgroundWebView(view, for: oldContext)
            recorder.contextWillLoad(replacement)
        }
        await Task.yield()

        XCTAssertNil(releasedView)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        XCTAssertEqual(recorder.snapshot().leakedBackgroundWebViewCount, 0)
    }

    private func makeContext() async throws -> WKWebExtensionContext {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CPMDiagnosticsTestExtension-\(UUID().uuidString)")
        let manifest = """
        {
            "manifest_version": 3,
            "name": "CPM Diagnostics Test Extension",
            "version": "1.0.0",
            "background": { "service_worker": "background.js" }
        }
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "// test".write(to: dir.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        createdTestExtensionDirs.append(dir)

        let webExtension = try await WKWebExtension(resourceBaseURL: dir)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = "cpm-diagnostics-test"
        return context
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class TestTab: NSObject, WKWebExtensionTab {
    private let webView: WKWebView?

    init(webView: WKWebView?) {
        self.webView = webView
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        webView
    }
}

/// Records every question WebKit or the recorder asks of the tab.
@available(macOS 15.4, iOS 18.4, *)
private final class RecordingTab: NSObject, WKWebExtensionTab {
    private let webView: WKWebView?
    private(set) var calls: [String] = []

    init(webView: WKWebView?) {
        self.webView = webView
    }

    func forgetCalls() {
        calls = []
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        calls.append("webView")
        return webView
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        calls.append("window")
        return nil
    }

    func indexInWindow(for context: WKWebExtensionContext) -> UInt {
        calls.append("indexInWindow")
        return 0
    }

    func parentTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        calls.append("parentTab")
        return nil
    }

    func title(for context: WKWebExtensionContext) -> String? {
        calls.append("title")
        return nil
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        calls.append("url")
        return nil
    }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        calls.append("pendingURL")
        return nil
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        calls.append("isLoadingComplete")
        return true
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        calls.append("isSelected")
        return false
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        calls.append("isPinned")
        return false
    }
}

/// Keeps a page load in progress: the request is never answered.
private final class NeverRespondingSchemeHandler: NSObject, WKURLSchemeHandler {
    var onStart: (() -> Void)?
    private var tasks: [any WKURLSchemeTask] = []

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        tasks.append(urlSchemeTask)
        onStart?()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
