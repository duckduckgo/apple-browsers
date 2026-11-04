//
//  CPMBackgroundLoadDiagnosticsTests.swift
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
final class CPMBackgroundLoadDiagnosticsTests: XCTestCase {
    typealias Name = CPMMessagingDiagnostics.ParameterName
    private var createdTestExtensionDirs: [URL] = []

    func testBackgroundReadinessFollowsTheLoadOfTheCurrentView() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date })
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.backgroundLoader = { _, completion in completions.append(completion) }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundReadyAfter], "none")
        XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundViewAge])

        let webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundReadyAfter], "pending")
        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundViewAge], "under_4s")

        await nextMainQueueTurn()
        XCTAssertEqual(completions.count, 1, "the load is requested on the next turn, not from inside WebKit's callback")
        date += 5.2
        completions[0](nil)
        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundReadyAfter], "4s_to_10s")
        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundViewAge], "4s_to_8s")
    }

    func testFailedBackgroundLoadIsReportedAsFailed() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.backgroundLoader = { _, completion in completions.append(completion) }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        await nextMainQueueTurn()

        completions.first?(NSError(domain: WKWebExtensionContext.errorDomain,
                                   code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue))

        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundReadyAfter], "failed")
    }

    func testLoadOfAReplacedBackgroundViewDoesNotMarkTheNewOneReady() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.backgroundLoader = { _, completion in completions.append(completion) }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let firstView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(firstView, for: context)
        await nextMainQueueTurn()
        let secondView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(secondView, for: context)

        completions.first?(nil)

        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundReadyAfter], "pending")
    }

    func testReadinessIsOmittedWhenBackgroundObservationIsDisabled() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: false)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, featureFlags: flags)
        var loadRequests = 0
        recorder.backgroundReadinessObserver.backgroundLoader = { _, _ in loadRequests += 1 }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundReadyAfter])

        let webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        await nextMainQueueTurn()

        XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundReadyAfter])
        XCTAssertEqual(loadRequests, 0)
    }

    func testResumeAppearsAsOneInterruptionEventInTheTimeline() {
        let recorder = makeRecorder()

        recorder.recordInterruption()

        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["interruption"])
    }

    func testBackToBackResumesCollapseIntoOneInterruptionEvent() {
        let recorder = makeRecorder()

        recorder.recordInterruption()
        recorder.recordInterruption()
        recorder.recordInterruption()

        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["interruption"])
    }

    func testInterruptionsAroundAnotherEventAreKeptSeparate() {
        let recorder = makeRecorder()
        let loadError = NSError(domain: WKWebExtensionContext.errorDomain,
                                code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue)

        recorder.recordInterruption()
        recorder.recordContextErrors([loadError])
        recorder.recordInterruption()

        let tokens = recorder.snapshot().backgroundEvents.map(\.token)
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(tokens.first, "interruption")
        XCTAssertTrue(tokens[1].hasPrefix("error_"))
        XCTAssertEqual(tokens.last, "interruption")
    }

    func testRepeatedSnapshotsDoNotRequestBackgroundLoads() async throws {
        let recorder = makeRecorder()
        var requests = 0
        recorder.backgroundReadinessObserver.backgroundLoader = { _, _ in requests += 1 }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let view = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(view, for: context)
        for _ in 0..<3 { _ = recorder.snapshot() }
        await nextMainQueueTurn()
        for _ in 0..<3 { _ = recorder.snapshot() }
        XCTAssertEqual(requests, 1)
    }

    func testFlagChangesInvalidateReadinessWithoutObservingAnOldView() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: false)
        let recorder = makeRecorder(flags: flags)
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.backgroundLoader = { _, completion in completions.append(completion) }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let first = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(first, for: context)
        await nextMainQueueTurn()
        XCTAssertTrue(completions.isEmpty)
        flags.isBackgroundDelegateProxyEnabled = true
        recorder.applyFeatureFlags()
        XCTAssertNil(recorder.snapshot().backgroundReadiness)
        let second = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(second, for: context)
        await nextMainQueueTurn()
        XCTAssertEqual(completions.count, 1)
        flags.isBackgroundDelegateProxyEnabled = false
        recorder.applyFeatureFlags()
        completions.first?(nil)
        XCTAssertNil(recorder.snapshot().backgroundReadiness)
        flags.isBackgroundDelegateProxyEnabled = true
        recorder.applyFeatureFlags()
        await nextMainQueueTurn()
        XCTAssertNil(recorder.snapshot().backgroundReadiness)
        XCTAssertEqual(completions.count, 1, "reenabling must not wake an old view for diagnostics")
        let third = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(third, for: context)
        XCTAssertEqual(recorder.snapshot().backgroundReadiness, .pending)
    }

    func testDisablingBeforeTheDeferredCallPreventsTheLoadRequest() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: true)
        let recorder = makeRecorder(flags: flags)
        var requests = 0
        recorder.backgroundReadinessObserver.backgroundLoader = { _, _ in requests += 1 }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let view = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(view, for: context)
        flags.isBackgroundDelegateProxyEnabled = false
        // Do not call applyFeatureFlags: the already queued observer must recheck the live flag itself.
        await nextMainQueueTurn()
        XCTAssertEqual(requests, 0)
        XCTAssertNil(recorder.snapshot().backgroundReadiness)
    }

    func testNewObservationRejectsAnOldCallbackForTheSameView() async throws {
        for stopsFirst in [false, true] {
            let observer = CPMBackgroundReadinessObserver(now: Date.init)
            var completions: [@MainActor (Error?) -> Void] = []
            observer.backgroundLoader = { _, completion in completions.append(completion) }
            let context = try await makeContext()
            let view = WKWebView(frame: .zero)
            observer.observe(view, in: context)
            await nextMainQueueTurn()
            if stopsFirst { observer.stopObserving() }
            observer.observe(view, in: context)
            await nextMainQueueTurn()
            XCTAssertEqual(completions.count, 2)
            completions.first?(nil)
            XCTAssertEqual(observer.readiness(of: view), .pending)
            completions.last?(nil)
            guard case .loaded = observer.readiness(of: view) else { return XCTFail("new observation must complete") }
        }
    }

    func testContextReplacementAndUnloadInvalidatePendingCallbacks() async throws {
        let recorder = makeRecorder()
        var completions: [@MainActor (Error?) -> Void] = []
        recorder.backgroundReadinessObserver.backgroundLoader = { _, completion in completions.append(completion) }
        let first = try await makeContext()
        let replacement = try await makeContext()
        recorder.contextWillLoad(first)
        let view = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(view, for: first)
        await nextMainQueueTurn()
        recorder.contextWillLoad(replacement)
        recorder.didCreateBackgroundWebView(view, for: replacement)
        await nextMainQueueTurn()
        completions.first?(nil)
        XCTAssertEqual(recorder.snapshot().backgroundReadiness, .pending)
        recorder.contextDidUnload(identifier: replacement.uniqueIdentifier)
        completions.last?(nil)
        XCTAssertEqual(recorder.snapshot().backgroundReadiness, .noBackground)
        XCTAssertNil(recorder.snapshot().secondsSinceBackgroundViewCreation)
    }

    func testError6KeepsItsOriginalTimeAndStateAndInvalidatesThePendingCallback() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        var state = CPMAppSessionDiagnostics.ApplicationState.active
        var stateReads = 0
        let session = CPMAppSessionDiagnostics(appVersionChange: nil, launchDate: date) { stateReads += 1; return state }
        let recorder = makeRecorder(now: { date }, appSession: session)
        var completion: (@MainActor (Error?) -> Void)?
        recorder.backgroundReadinessObserver.backgroundLoader = { _, callback in completion = callback }
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let view = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(view, for: context)
        await nextMainQueueTurn()
        date += 30.4
        let error = loadError()
        recorder.recordContextErrors([error])
        state = .background
        date += 60
        recorder.recordContextErrors([error])
        completion?(nil)
        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundReadiness, .failed)
        XCTAssertEqual(snapshot.secondsFromBackgroundViewToLoadError ?? -1, 30.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.backgroundLoadParameters[Name.backgroundLoadErrorAfter], "25s_to_35s")
        XCTAssertEqual(snapshot.backgroundLoadParameters[Name.backgroundLoadErrorAppState], "active")
        XCTAssertEqual(stateReads, 1, "state belongs to the error, not a later snapshot/notification")
    }

    func testHistoricalErrorIsNotAttributedToAReplacementView() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let recorder = makeRecorder(now: { date })
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let first = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(first, for: context)
        let historical = loadError()
        date += 30
        recorder.recordContextErrors([historical])
        let replacement = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(replacement, for: context)
        date += 6
        recorder.recordContextErrors([historical, NSError(domain: "unrelated", code: 6)])
        XCTAssertEqual(recorder.snapshot().hasBackgroundLoadError, false)
        XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundLoadErrorAfter])
        recorder.recordContextErrors([historical, loadError()])
        XCTAssertEqual(recorder.snapshot().backgroundLoadParameters[Name.backgroundLoadErrorAfter], "5s_to_25s")
        XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundLoadErrorAppState])
        recorder.contextWillLoad(try await makeContext())
        XCTAssertEqual(recorder.snapshot().hasBackgroundLoadError, false)
    }

    func testCopiedHistoricalErrorsDoNotFailTheReplacementLoadButAnAdditionalErrorDoes() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let recorder = makeRecorder(now: { date })
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let first = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(first, for: context)
        let historical = loadError()
        date += 30
        recorder.recordContextErrors([historical])
        let replacement = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(replacement, for: context)
        date += 6

        // The release branch's safe errors getter returns fresh NSError copies on every read.
        recorder.recordContextErrors([NSError(copyingObject: historical)])
        XCTAssertEqual(recorder.snapshot().hasBackgroundLoadError, false)
        XCTAssertNil(recorder.snapshot().secondsFromBackgroundViewToLoadError)
        XCTAssertEqual(recorder.snapshot().backgroundReadiness, .pending)

        // WebKit can append a genuinely new failure with the same domain, code and userInfo.
        recorder.recordContextErrors([NSError(copyingObject: historical), NSError(copyingObject: historical)])
        XCTAssertEqual(recorder.snapshot().backgroundReadiness, .failed)
        XCTAssertEqual(try XCTUnwrap(recorder.snapshot().secondsFromBackgroundViewToLoadError), 6, accuracy: 0.001)
        date += 60
        recorder.recordContextErrors([NSError(copyingObject: historical), NSError(copyingObject: historical)])
        XCTAssertEqual(try XCTUnwrap(recorder.snapshot().secondsFromBackgroundViewToLoadError), 6, accuracy: 0.001)
    }

    func testErrorsWithoutAnObservedLoadOrWithOtherCodesAreOmitted() async throws {
        let recorder = makeRecorder()
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let historical = loadError()
        recorder.recordContextErrors([historical])
        XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundLoadErrorAfter])
        let view = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(view, for: context)
        recorder.recordContextErrors([historical, NSError(domain: "other", code: 6),
                                      NSError(domain: WKWebExtensionContext.errorDomain, code: 7)])
        XCTAssertEqual(recorder.snapshot().hasBackgroundLoadError, false)
        XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundLoadErrorAppState])
    }

    func testFailedLoadRemainsFailedWithoutItsViewAndResetsForTheNextAttempt() async throws {
        for errorBeforeDeallocation in [true, false] {
            var date = Date(timeIntervalSince1970: 1000)
            let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: true)
            let recorder = makeRecorder(now: { date }, flags: flags)
            let context = try await makeContext()
            recorder.contextWillLoad(context)
            weak var released: WKWebView?
            autoreleasepool {
                let view = WKWebView(frame: .zero)
                released = view
                recorder.didCreateBackgroundWebView(view, for: context)
                date += 30
                if errorBeforeDeallocation { recorder.recordContextErrors([loadError()]) }
            }
            await nextMainQueueTurn()
            XCTAssertNil(released)
            if !errorBeforeDeallocation { recorder.recordContextErrors([loadError()]) }

            let snapshot = recorder.snapshot()
            XCTAssertEqual(snapshot.backgroundReadiness, .failed)
            XCTAssertEqual(snapshot.backgroundWebViewAlive, false)
            XCTAssertEqual(snapshot.backgroundLoadParameters[Name.backgroundLoadErrorAfter], "25s_to_35s")
            XCTAssertNil(snapshot.secondsSinceBackgroundViewCreation)

            flags.isBackgroundDelegateProxyEnabled = false
            recorder.applyFeatureFlags()
            XCTAssertNil(recorder.snapshot().backgroundReadiness)
            flags.isBackgroundDelegateProxyEnabled = true
            recorder.applyFeatureFlags()
            XCTAssertEqual(recorder.snapshot().backgroundReadiness, .failed)

            let replacement = WKWebView(frame: .zero)
            recorder.didCreateBackgroundWebView(replacement, for: context)
            withExtendedLifetime(replacement) {
                XCTAssertEqual(recorder.snapshot().backgroundReadiness, .pending)
                XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundLoadErrorAfter])
            }
            recorder.contextWillLoad(try await makeContext())
            XCTAssertEqual(recorder.snapshot().backgroundReadiness, .noBackground)
            XCTAssertNil(recorder.snapshot().backgroundLoadParameters[Name.backgroundLoadErrorAfter])
        }
    }

    private func makeRecorder(now: @escaping () -> Date = Date.init, appSession: CPMAppSessionDiagnostics? = nil,
                              flags: CPMDiagnosticsStaticFeatureFlags? = nil) -> CPMMessagingDiagnosticsRecorder {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false,
                                                       featureFlags: flags, now: now, appSession: appSession)
        recorder.backgroundReadinessObserver.backgroundLoader = { _, _ in }
        return recorder
    }

    private func loadError() -> NSError {
        NSError(domain: WKWebExtensionContext.errorDomain, code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue)
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    override func tearDown() {
        for dir in createdTestExtensionDirs { try? FileManager.default.removeItem(at: dir) }
        createdTestExtensionDirs.removeAll()
        super.tearDown()
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
