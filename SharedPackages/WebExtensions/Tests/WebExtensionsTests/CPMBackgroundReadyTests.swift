//
//  CPMBackgroundReadyTests.swift
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

private typealias Name = CPMMessagingDiagnostics.ParameterName

/// The success-side baseline: one `cpmBackgroundReady` pixel for every background start the recorder observes,
/// so failure pixels have a denominator.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadyPixelTests: XCTestCase {

    private var extensionDirectories: [URL] = []

    override func tearDown() {
        extensionDirectories.forEach { try? FileManager.default.removeItem(at: $0) }
        extensionDirectories = []
        super.tearDown()
    }

    func testFirstViewOfAContextLoadReportsHowLongTheLoadTookAndWhatPrecededIt() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let harness = try await makeHarness(now: { date })
        harness.recorder.contextWillLoad(harness.context)
        date += 0.6
        harness.createBackgroundView()
        await nextMainQueueTurn()
        date += 2.5
        harness.completions[0](nil)

        let details = try XCTUnwrap(harness.pixels.readyDetails.first)
        XCTAssertEqual(harness.pixels.readyDetails.count, 1)
        XCTAssertEqual(details.kind, .contextLoad)
        XCTAssertEqual(details.pixelParameters[Name.backgroundReadyAfter], "1s_to_4s")
        XCTAssertEqual(details.pixelParameters[Name.contextLoadToBackgroundView], "250ms_to_1s")
        XCTAssertEqual(details.pixelParameters[Name.applicationState], "active")
        XCTAssertEqual(details.pixelParameters[Name.resumeAge], "under_30s")
        XCTAssertEqual(details.pixelParameters[Name.thermalState], "fair")
        XCTAssertEqual(details.pixelParameters[Name.lowPowerMode], "true")
        XCTAssertEqual(details.pixelParameters[Name.lockdownMode], "false")
    }

    func testLaterViewsAreWakesAndDoNotRepeatTheContextLoadTime() async throws {
        let harness = try await makeHarness()
        harness.recorder.contextWillLoad(harness.context)
        harness.createBackgroundView()
        await nextMainQueueTurn()
        harness.completions[0](nil)

        harness.createBackgroundView()
        await nextMainQueueTurn()
        harness.completions[1](nil)

        XCTAssertEqual(harness.pixels.readyDetails.map(\.kind), [.contextLoad, .wake])
        XCTAssertNotNil(harness.pixels.readyDetails[0].pixelParameters[Name.contextLoadToBackgroundView])
        XCTAssertNil(harness.pixels.readyDetails[1].pixelParameters[Name.contextLoadToBackgroundView])
    }

    func testAFailedLoadIsReportedAsFailedNotDropped() async throws {
        let harness = try await makeHarness()
        harness.recorder.contextWillLoad(harness.context)
        harness.createBackgroundView()
        await nextMainQueueTurn()

        harness.completions[0](NSError(domain: WKWebExtensionContext.errorDomain,
                                       code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue))

        XCTAssertEqual(harness.pixels.readyDetails.first?.pixelParameters[Name.backgroundReadyAfter], "failed")
    }

    func testALoadThatEndsAfterItsViewWasReplacedIsNotReported() async throws {
        let harness = try await makeHarness()
        harness.recorder.contextWillLoad(harness.context)
        harness.createBackgroundView()
        await nextMainQueueTurn()
        harness.createBackgroundView()
        await nextMainQueueTurn()

        harness.completions[0](nil)

        XCTAssertTrue(harness.pixels.readyDetails.isEmpty, "the first view is gone; only the current view's load counts")
    }

    func testNothingIsReportedWhenBackgroundObservationIsDisabled() async throws {
        let flags = CPMDiagnosticsStaticFeatureFlags(isBackgroundDelegateProxyEnabled: false)
        let harness = try await makeHarness(featureFlags: flags)
        harness.recorder.contextWillLoad(harness.context)
        harness.createBackgroundView()
        await nextMainQueueTurn()

        XCTAssertTrue(harness.completions.isEmpty)
        XCTAssertTrue(harness.pixels.readyDetails.isEmpty)
    }

    func testTheContextLoadTimeIsMeasuredAgainForTheNextContextLoad() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let harness = try await makeHarness(now: { date })
        harness.recorder.contextWillLoad(harness.context)
        date += 5
        harness.createBackgroundView()
        XCTAssertEqual(harness.recorder.snapshot().pixelParameters[Name.contextLoadToBackgroundView], "4s_to_10s")

        harness.recorder.contextWillLoad(harness.context)
        XCTAssertNil(harness.recorder.snapshot().pixelParameters[Name.contextLoadToBackgroundView], "a new load has no view yet")
        date += 0.1
        harness.createBackgroundView()
        XCTAssertEqual(harness.recorder.snapshot().pixelParameters[Name.contextLoadToBackgroundView], "under_250ms")
    }

    func testFailureSnapshotsCarryTheDeviceStateAndTimeSinceResume() async throws {
        let harness = try await makeHarness()

        let parameters = harness.recorder.snapshot().pixelParameters

        XCTAssertEqual(parameters[Name.lowPowerMode], "true")
        XCTAssertEqual(parameters[Name.thermalState], "fair")
        XCTAssertEqual(parameters[Name.lockdownMode], "false")
        XCTAssertEqual(parameters[Name.resumeAge], "under_30s")
    }

    func testBackgroundReadyPixelMetadata() throws {
        let details = CPMBackgroundReadyDetails(kind: .wake, readiness: .loaded(secondsAfterViewCreation: 12))

        let metadata = try XCTUnwrap(CPMWebExtensionPixelMetadata(event: .cpmBackgroundReady(details)))

        XCTAssertEqual(metadata.name, "debug_web_extension_cpm_background_ready_wake")
        XCTAssertEqual(metadata.frequency, .daily)
        XCTAssertEqual(metadata.parameters, [Name.backgroundReadyAfter: "10s_to_30s"])
        let contextLoad = CPMBackgroundReadyDetails(kind: .contextLoad, readiness: .failed)
        XCTAssertEqual(CPMWebExtensionPixelMetadata(event: .cpmBackgroundReady(contextLoad))?.name,
                       "debug_web_extension_cpm_background_ready_context_load")
    }

    // MARK: - Helpers

    @MainActor
    private final class Harness {
        let recorder: CPMMessagingDiagnosticsRecorder
        let context: WKWebExtensionContext
        let pixels: CapturingReadyPixelFiring
        /// Completion handlers of every `loadBackgroundContent` request, in order.
        let completions: Completions
        /// The recorder and its observer hold background views weakly, as WebKit owns them; the test must too.
        private var views: [WKWebView] = []

        init(recorder: CPMMessagingDiagnosticsRecorder,
             context: WKWebExtensionContext,
             pixels: CapturingReadyPixelFiring,
             completions: Completions) {
            self.recorder = recorder
            self.context = context
            self.pixels = pixels
            self.completions = completions
        }

        func createBackgroundView() {
            let view = WKWebView(frame: .zero)
            views.append(view)
            recorder.didCreateBackgroundWebView(view, for: context)
        }
    }

    /// A box, so the observer's closure and the test see the same list.
    private final class Completions {
        private var handlers: [@MainActor (Error?) -> Void] = []
        var isEmpty: Bool { handlers.isEmpty }
        func append(_ handler: @escaping @MainActor (Error?) -> Void) { handlers.append(handler) }
        subscript(index: Int) -> @MainActor (Error?) -> Void { handlers[index] }
    }

    private func makeHarness(now: @escaping () -> Date = Date.init,
                             featureFlags: (any CPMDiagnosticsFeatureFlagsProviding)? = nil) async throws -> Harness {
        let pixels = CapturingReadyPixelFiring()
        let resume = now()
        let session = CPMAppSessionDiagnostics(appVersionChange: nil,
                                               launchDate: now(),
                                               applicationState: { .active },
                                               lastResumeDate: { resume })
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil },
                                                       observesMemoryPressure: false,
                                                       featureFlags: featureFlags,
                                                       now: now,
                                                       appSession: session,
                                                       pixelFiring: pixels,
                                                       deviceState: {
            CPMDeviceState(isLowPowerMode: true, thermalState: .fair, isLockdownMode: false)
        })
        let completions = Completions()
        recorder.backgroundReadinessObserver.loadBackgroundContent = { _, completion in completions.append(completion) }
        return Harness(recorder: recorder, context: try await makeContext(), pixels: pixels, completions: completions)
    }

    private func makeContext() async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CPMBackgroundReadyTests-\(UUID().uuidString)")
        let manifest = """
        { "manifest_version": 3, "name": "CPM Ready Test Extension", "version": "1.0.0", "background": { "service_worker": "background.js" } }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "// test".write(to: directory.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        extensionDirectories.append(directory)
        return WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingReadyPixelFiring: WebExtensionPixelFiring {
    private(set) var readyDetails: [CPMBackgroundReadyDetails] = []

    func fire(_ event: WebExtensionPixelEvent) {
        guard case .cpmBackgroundReady(let details) = event else { return }
        readyDetails.append(details)
    }
}

/// Bucketing of the values added to the failure and baseline pixels.
final class CPMDeviceDiagnosticsTests: XCTestCase {

    func testContextLoadDelayIsBucketedAroundTheCacheClearingDelay() {
        XCTAssertEqual(CPMMessagingDiagnostics.contextLoadDelayBucket(0.02), "under_250ms")
        XCTAssertEqual(CPMMessagingDiagnostics.contextLoadDelayBucket(0.25), "250ms_to_1s")
        XCTAssertEqual(CPMMessagingDiagnostics.contextLoadDelayBucket(0.999), "250ms_to_1s")
        XCTAssertEqual(CPMMessagingDiagnostics.contextLoadDelayBucket(1), "1s_to_4s")
        XCTAssertEqual(CPMMessagingDiagnostics.contextLoadDelayBucket(4), "4s_to_10s")
        XCTAssertEqual(CPMMessagingDiagnostics.contextLoadDelayBucket(10), "over_10s")
    }

    func testResumeAgeIsBucketed() {
        XCTAssertEqual(CPMMessagingDiagnostics.resumeAgeBucket(0), "under_30s")
        XCTAssertEqual(CPMMessagingDiagnostics.resumeAgeBucket(30), "30s_to_2m")
        XCTAssertEqual(CPMMessagingDiagnostics.resumeAgeBucket(120), "2m_to_10m")
        XCTAssertEqual(CPMMessagingDiagnostics.resumeAgeBucket(600), "over_10m")
    }

    func testDeviceStateParametersUseTheFixedVocabulary() {
        let state = CPMDeviceState(isLowPowerMode: false, thermalState: .critical, isLockdownMode: true)

        XCTAssertEqual(state.pixelParameters, [Name.lowPowerMode: "false", Name.thermalState: "critical", Name.lockdownMode: "true"])
    }

    @MainActor
    func testLiveDeviceStateIsReadableAndUsesTheFixedVocabulary() {
        let state = CPMDeviceState.current()

        XCTAssertTrue(["nominal", "fair", "serious", "critical"].contains(state.thermalState.rawValue))
    }

    func testDiagnosticsWithoutDeviceFactsOmitThem() {
        let parameters = CPMMessagingDiagnostics().pixelParameters

        for name in [Name.lowPowerMode, Name.thermalState, Name.lockdownMode, Name.resumeAge, Name.contextLoadToBackgroundView] {
            XCTAssertNil(parameters[name], "\(name) must be omitted when unknown")
        }
    }
}

/// Whether the user can use the device and when it last resumed, as reported by notifications the app names.
@MainActor
final class CPMPresenceTrackerTests: XCTestCase {

    func testAStartedTrackerHasAUserAndNoResume() {
        let tracker = CPMPresenceTracker()

        XCTAssertFalse(tracker.isUserAway)
        XCTAssertNil(tracker.lastResumeDate)
    }

    func testTheUserIsAwayWhileTheScreenIsLockedOrAsleep() {
        let tracker = CPMPresenceTracker()

        tracker.record(.screenLocked)
        XCTAssertTrue(tracker.isUserAway)
        tracker.record(.screenSlept)
        tracker.record(.screenUnlocked)
        XCTAssertTrue(tracker.isUserAway, "unlocked but the display is still asleep")
        tracker.record(.screenWoke)
        XCTAssertFalse(tracker.isUserAway)
    }

    func testResumeRecordsTheTimeFromTheInjectedClock() {
        let moment = Date(timeIntervalSince1970: 4242)
        let tracker = CPMPresenceTracker(now: { moment })

        tracker.record(.resumed)

        XCTAssertEqual(tracker.lastResumeDate, moment)
        XCTAssertFalse(tracker.isUserAway, "waking the system says nothing about the screen")
    }

    func testObservedNotificationsAreRecordedAsTheirSignal() async throws {
        let center = NotificationCenter()
        let lock = Notification.Name("test.lock")
        let wake = Notification.Name("test.wake")
        let tracker = CPMPresenceTracker()
        tracker.observe(lock, on: center, as: .screenLocked)
        tracker.observe(wake, on: center, as: .resumed)

        center.post(name: lock, object: nil)
        center.post(name: wake, object: nil)
        for _ in 0..<200 where !(tracker.isUserAway && tracker.lastResumeDate != nil) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(tracker.isUserAway)
        XCTAssertNotNil(tracker.lastResumeDate)
    }
}
