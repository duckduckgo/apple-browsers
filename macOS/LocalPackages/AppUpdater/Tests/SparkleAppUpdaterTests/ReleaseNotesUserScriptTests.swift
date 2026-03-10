//
//  ReleaseNotesUserScriptTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppUpdaterShared
import Combine
import Common
import Navigation
import Persistence
import PersistenceTestingUtils
import PixelKit
import UserScript
import WebKit
import XCTest

@testable import SparkleAppUpdater

final class ReleaseNotesUserScriptTests: XCTestCase {

    private let releaseNotesURL = URL(string: "duck://release-notes")!

    /// Regression test: `onUpdate()` must push state to the page even when the script
    /// has never received `initialSetup`. This simulates the race where
    /// `contentBlockingAssets` replaces the script instance after page init.
    @MainActor
    func testOnUpdatePushesStateWhenWebViewIsSet() throws {
        // onUpdate() early-returns when runType is .uiTests (e.g. CI sets CI=true)
        try XCTSkipIf(AppVersion.runType == .uiTests, "onUpdate() is disabled in UI test environments")

        let controller = StubSparkleUpdateController()
        let store = InMemoryThrowingKeyValueStore()
        let script = ReleaseNotesUserScript(
            updateController: controller,
            pixelFiring: nil,
            keyValueStore: store,
            releaseNotesURL: releaseNotesURL
        )

        // requiresRunInPageContentWorld makes push() call the overridable evaluateJavaScript(_:completionHandler:)
        let broker = UserScriptMessageBroker(context: "releaseNotes", requiresRunInPageContentWorld: true)
        script.with(broker: broker)

        let mockWebView = MockURLWebView(url: releaseNotesURL)
        let jsExpectation = expectation(description: "evaluateJavaScript called")
        mockWebView.onEvaluateJavaScript = {
            jsExpectation.fulfill()
        }

        // Assigning the webView triggers onUpdate() via didSet
        script.webView = mockWebView

        // broker.push dispatches evaluateJavaScript asynchronously on main
        wait(for: [jsExpectation], timeout: 2.0)
    }

    // MARK: - releaseNotesEmpty pixel debounce tests

    /// The pixel must NOT fire when `loadingError` resolves to `loaded` within 1 second.
    @MainActor
    func testReleaseNotesEmptyPixelDoesNotFireWhenNotesLoadWithinDebounce() throws {
        try XCTSkipIf(AppVersion.runType == .uiTests, "onUpdate() is disabled in UI test environments")

        let controller = StubSparkleUpdateController()
        let pixelMock = CapturingPixelFiring()
        let store = InMemoryThrowingKeyValueStore()
        let script = ReleaseNotesUserScript(
            updateController: controller,
            pixelFiring: pixelMock,
            keyValueStore: store,
            releaseNotesURL: releaseNotesURL
        )

        let broker = UserScriptMessageBroker(context: "releaseNotes", requiresRunInPageContentWorld: true)
        script.with(broker: broker)

        let mockWebView = MockURLWebView(url: releaseNotesURL)
        script.webView = mockWebView

        // First call: no latestUpdate, no cache → loadingError, starts 1s timer
        script.onUpdate()
        XCTAssertTrue(pixelMock.firedEvents.isEmpty, "Pixel should not fire immediately")

        // Simulate notes loading before the 1s timer fires
        controller.latestUpdate = Update.stub()
        script.onUpdate()

        // Wait longer than the debounce interval to confirm it was cancelled
        let waitExpectation = expectation(description: "wait for debounce window to pass")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            waitExpectation.fulfill()
        }
        wait(for: [waitExpectation], timeout: 2.0)

        XCTAssertTrue(pixelMock.firedEvents.isEmpty, "Pixel should not fire when notes load within debounce window")
    }

    /// The pixel MUST fire when `loadingError` persists past the 1-second debounce.
    @MainActor
    func testReleaseNotesEmptyPixelFiresWhenErrorPersists() throws {
        try XCTSkipIf(AppVersion.runType == .uiTests, "onUpdate() is disabled in UI test environments")

        let controller = StubSparkleUpdateController()
        let pixelMock = CapturingPixelFiring()
        let store = InMemoryThrowingKeyValueStore()
        let script = ReleaseNotesUserScript(
            updateController: controller,
            pixelFiring: pixelMock,
            keyValueStore: store,
            releaseNotesURL: releaseNotesURL
        )

        let broker = UserScriptMessageBroker(context: "releaseNotes", requiresRunInPageContentWorld: true)
        script.with(broker: broker)

        let mockWebView = MockURLWebView(url: releaseNotesURL)
        script.webView = mockWebView

        // Call with no latestUpdate, no cache → loadingError
        script.onUpdate()
        XCTAssertTrue(pixelMock.firedEvents.isEmpty, "Pixel should not fire immediately")

        // Wait for debounce to elapse
        let fireExpectation = expectation(description: "pixel should fire after debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            fireExpectation.fulfill()
        }
        wait(for: [fireExpectation], timeout: 2.0)

        XCTAssertEqual(pixelMock.firedEvents.count, 1, "Pixel should fire once after debounce")
        XCTAssertEqual(pixelMock.firedEvents.first?.name, UpdateFlowPixels.releaseNotesLoadingError.name)
    }
}

// MARK: - Test Helpers

/// Mock WKWebView that returns a fixed URL and records evaluateJavaScript calls.
private final class MockURLWebView: WKWebView {
    private let mockedURL: URL
    var onEvaluateJavaScript: (() -> Void)?

    init(url: URL) {
        self.mockedURL = url
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var url: URL? { mockedURL }

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, (any Error)?) -> Void)? = nil) {
        onEvaluateJavaScript?()
    }
}

/// Minimal stub implementing SparkleUpdateControlling for testing ReleaseNotesValues construction.
private final class StubSparkleUpdateController: NSObject, SparkleUpdateControlling {

    var isAtRestartCheckpoint = false
    var shouldForceUpdateCheck = false
    var useLegacyAutoRestartLogic = false

    var willRelaunchAppPublisher: AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }

    func checkForUpdateRespectingRollout() {}
    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress) {}
    func log() {}

    func makeReleaseNotesNavigationResponder(
        releaseNotesURL: URL,
        scriptsPublisher: some Publisher<any ReleaseNotesUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>
    ) -> any NavigationResponder & AnyObject {
        fatalError("Not expected")
    }

    func makeReleaseNotesUserScript(
        pixelFiring: PixelFiring?,
        keyValueStore: ThrowingKeyValueStoring,
        releaseNotesURL: URL
    ) -> Subfeature {
        fatalError("Not expected")
    }

    func runUpdateFromMenuItem() {}

    @Published var latestUpdate: Update?
    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    var mustShowUpdateIndicators = false
    var needsNotificationDot = false
    var notificationDotPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var clearsNotificationDotOnMenuOpen = true
    var lastUpdateCheckDate: Date?
    var lastUpdateNotificationShownDate = Date.distantPast

    @Published var updateProgress: UpdateCycleProgress = .updateCycleNotStarted
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    var areAutomaticUpdatesEnabled = false
    var notificationPresenter: any UpdateNotificationPresenting = StubUpdateNotificationPresenter()

    func runUpdate() {}
    func checkForUpdateSkippingRollout() {}
    func openUpdatesPage() {}
    func handleAppTermination() {}
}

private final class CapturingPixelFiring: PixelFiring {
    var firedEvents: [PixelKitEvent] = []

    func fire(_ event: PixelKitEvent,
              frequency: PixelKit.Frequency,
              withAdditionalParameters: [String: String]?,
              onComplete: @escaping PixelKit.CompletionBlock) {
        firedEvents.append(event)
    }
}

private extension Update {
    static func stub() -> Update {
        Update(isInstalled: true,
               type: .regular,
               version: "1.0.0",
               build: "100",
               date: Date(),
               releaseNotes: ["Some notes"],
               releaseNotesSubscription: [],
               needsLatestReleaseNote: false)
    }
}

private final class StubUpdateNotificationPresenter: UpdateNotificationPresenting {
    func showUpdateNotification(for status: AppUpdateStatus) {}
    func showUpdateNotification(for type: Update.UpdateType, areAutomaticUpdatesEnabled: Bool) {}
    func dismissIfPresented() {}
    func openUpdatesPage() {}
}
