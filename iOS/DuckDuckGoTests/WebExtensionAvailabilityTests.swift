//
//  WebExtensionAvailabilityTests.swift
//  DuckDuckGo
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

import XCTest
@_spi(Testing) import Persistence
@testable import DuckDuckGo
import BrowserServicesKit
import Core
import WebExtensions
import WebExtensionsTestSupport
import WebKit

@available(iOS 18.4, *)
final class WebExtensionAvailabilityTests: XCTestCase {

    func testWhenAppRelaunchesThenVersionComparisonIsCachedPerSession() {
        let store = InMemoryKeyValueStore()
        let first = AppSessionInfo(keyValueStore: store, version: "1.0.100")
        XCTAssertNil(first.appVersionChange)
        let restart = AppSessionInfo(keyValueStore: store, version: "1.0.100")
        XCTAssertNil(restart.appVersionChange)
        let update = AppSessionInfo(keyValueStore: store, version: "1.0.101")
        XCTAssertEqual(update.appVersionChange, .updated)
        let nextRestart = AppSessionInfo(keyValueStore: store, version: "1.0.101")
        XCTAssertNil(nextRestart.appVersionChange)
        XCTAssertEqual(update.appVersionChange, .updated)
        XCTAssertNil(first.appVersionChange)
        XCTAssertEqual(AppSessionInfo(keyValueStore: store, version: "1.0.100").appVersionChange, .downgraded)
    }

    func testWhenAppSessionIsCreatedThenUsesGenericStorageKeyAndProvidedLaunchDate() {
        let store = InMemoryKeyValueStore()
        let launchDate = Date(timeIntervalSince1970: 1000)
        let session = AppSessionInfo(keyValueStore: store, version: "1.2.3", launchDate: launchDate)
        XCTAssertEqual(store.object(forKey: "app-session.previous-app-version") as? String, "1.2.3")
        XCTAssertEqual(session.launchDate, launchDate)
        XCTAssertNil(session.appVersionChange)
    }

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockWebExtensionManager: MockWebExtensionManaging!
    private var extensionDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enabledFeatureFlags = [.webExtensions, .embeddedExtension]
        mockWebExtensionManager = MockWebExtensionManaging()
    }

    override func tearDown() {
        extensionDirectories.forEach { try? FileManager.default.removeItem(at: $0) }
        extensionDirectories = []
        mockFeatureFlagger = nil
        mockWebExtensionManager = nil
        super.tearDown()
    }

    private func makeSUT(isNativeMessagingSupported: Bool = true) -> WebExtensionAvailability {
        WebExtensionAvailability(
            featureFlagger: mockFeatureFlagger,
            nativeMessagingSupport: NativeMessagingSupport(isSupported: isNativeMessagingSupported),
            webExtensionManagerProvider: { [mockWebExtensionManager] in mockWebExtensionManager }
        )
    }

    // MARK: - isAvailable

    func testWhenWebExtensionsFlagIsOnThenWebExtensionsAreAvailable() {
        XCTAssertTrue(makeSUT().isAvailable)
    }

    func testWhenWebExtensionsFlagIsOffThenWebExtensionsAreNotAvailable() {
        mockFeatureFlagger.enabledFeatureFlags = [.embeddedExtension]

        XCTAssertFalse(makeSUT().isAvailable)
    }

    // MARK: - isAutoconsentExtensionAvailable

    @MainActor
    func testWhenEmbeddedExtensionIsLoadedThenAutoconsentExtensionIsAvailable() async throws {
        try await loadEmbeddedExtension()

        XCTAssertTrue(makeSUT().isAutoconsentExtensionAvailable)
    }

    // The Alpha case: loaded, but unable to reach the app, so the native script has to take over.
    @MainActor
    func testWhenNativeMessagingIsNotSupportedThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadEmbeddedExtension()

        XCTAssertFalse(makeSUT(isNativeMessagingSupported: false).isAutoconsentExtensionAvailable)
    }

    @MainActor
    func testWhenOnlyAnotherExtensionIsLoadedThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadExtension(withIdentifier: DuckDuckGoWebExtensionType.darkReader.rawValue)

        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    func testWhenNoExtensionIsLoadedThenAutoconsentExtensionIsNotAvailable() {
        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    @MainActor
    func testWhenWebExtensionsFlagIsOffThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadEmbeddedExtension()
        mockFeatureFlagger.enabledFeatureFlags = [.embeddedExtension]

        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    @MainActor
    func testWhenEmbeddedExtensionFlagIsOffThenAutoconsentExtensionIsNotAvailable() async throws {
        try await loadEmbeddedExtension()
        mockFeatureFlagger.enabledFeatureFlags = [.webExtensions]

        XCTAssertFalse(makeSUT().isAutoconsentExtensionAvailable)
    }

    // MARK: - Helpers

    @MainActor
    private func loadEmbeddedExtension() async throws {
        try await loadExtension(withIdentifier: DuckDuckGoWebExtensionType.embedded.rawValue)
    }

    // The type is read from the manifest, so the fixture only needs an id.
    @MainActor
    private func loadExtension(withIdentifier identifier: String) async throws {
        let manifest = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.0",
            "browser_specific_settings": {
                "duckduckgo": {
                    "id": "\(identifier)"
                }
            }
        }
        """

        let extensionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebExtensionAvailabilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        extensionDirectories.append(extensionDirectory)

        try manifest.write(to: extensionDirectory.appendingPathComponent("manifest.json"),
                           atomically: true,
                           encoding: .utf8)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionDirectory)
        mockWebExtensionManager.loadedExtensions = [WKWebExtensionContext(for: webExtension)]
    }
}

@available(iOS 18.4, *)
@MainActor
final class WebExtensionNavigationCancellationTests: XCTestCase {

    func testWhenNavigationIsInvalidatedThenDecisionIsCancelledWithoutOpeningSharedGate() async throws {
        let actions: [(String, (TabViewController) -> Void)] = [
            ("Stop", { $0.stopLoading() }),
            ("New URL", { $0.load(url: URL(string: "https://example.com/new")!) }),
            ("Close", { $0.closeSitePermissions() }),
            ("Fire", { $0.prepareForDataClearing() })
        ]
        for (name, invalidate) in actions {
            let coordinator = WebExtensionLifecycleCoordinator(manager: MockWebExtensionManaging(),
                                                                initialLoadTimeout: 60,
                                                                enabledTypesProvider: { [.embedded] })
            defer { coordinator.cancelAll() }
            let waiter = try XCTUnwrap(coordinator.initialLoadWaiter)
            let started = expectation(description: "\(name): waiting for extension startup")
            let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                             webExtensionInitialLoadWaiterProvider: {
                return {
                    started.fulfill()
                    await waiter()
                }
            })
            tab.specialErrorPageNavigationHandler.delegate = nil
            defer { tab.prepareForDataClearing() }
            let webView = try XCTUnwrap(tab.webView as? MockWebView)
            let cancelled = expectation(description: "\(name): pending decision cancelled")
            cancelled.assertForOverFulfill = true
            tab.webView(webView, decidePolicyFor: makeNavigationAction()) { policy in
                XCTAssertEqual(policy, .cancel, name)
                cancelled.fulfill()
            }
            await fulfillment(of: [started], timeout: 1)
            invalidate(tab)
            let loadCount = webView.loadCallCount
            await fulfillment(of: [cancelled], timeout: 1)
            XCTAssertEqual(webView.loadCallCount, loadCount, "Cancelled policy must not start a replacement load")
            XCTAssertNotNil(coordinator.initialLoadWaiter, "Cancelling one navigation must not open the shared gate")
        }
    }

    func testWhenSupersededWaitFinishesThenReplacementWaitCanStillBeCancelled() async throws {
        var continuations = [CheckedContinuation<Void, Never>]()
        defer { continuations.forEach { $0.resume() } }
        let firstStarted = expectation(description: "First wait started")
        let secondStarted = expectation(description: "Replacement wait started")
        let tab = TabViewController.fake(customWebView: { MockWebView(frame: .zero, configuration: $0) },
                                         webExtensionInitialLoadWaiterProvider: {
            return {
                // Intentionally ignore cancellation to exercise the check after await.
                await withCheckedContinuation { continuation in
                    continuations.append(continuation)
                    (continuations.count == 1 ? firstStarted : secondStarted).fulfill()
                }
            }
        })
        tab.specialErrorPageNavigationHandler.delegate = nil
        defer { tab.prepareForDataClearing() }
        let webView = try XCTUnwrap(tab.webView as? MockWebView)
        let firstCancelled = expectation(description: "Superseded decision cancelled")
        firstCancelled.assertForOverFulfill = true
        tab.webView(webView, decidePolicyFor: makeNavigationAction()) { policy in
            XCTAssertEqual(policy, .cancel)
            firstCancelled.fulfill()
        }
        await fulfillment(of: [firstStarted], timeout: 1)
        let secondCancelled = expectation(description: "Replacement decision cancelled by Stop")
        secondCancelled.assertForOverFulfill = true
        tab.webView(webView, decidePolicyFor: makeNavigationAction()) { policy in
            XCTAssertEqual(policy, .cancel)
            secondCancelled.fulfill()
        }
        await fulfillment(of: [secondStarted], timeout: 1)
        guard continuations.count == 2 else {
            XCTFail("Both navigation waits must have started")
            return
        }
        continuations.removeFirst().resume()
        await fulfillment(of: [firstCancelled], timeout: 1)
        tab.stopLoading()
        continuations.removeFirst().resume()
        await fulfillment(of: [secondCancelled], timeout: 1)
        XCTAssertEqual(webView.loadCallCount, 0, "Neither stale policy may start a replacement load")
    }

    private func makeNavigationAction() -> WKNavigationAction {
        let request = URLRequest(url: URL(string: "https://example.com/old")!)
        return MockNavigationAction(request: request, navigationType: .other,
                                    targetFrame: .mock(isMainFrame: true, securityOriginHost: "example.com", request: request))
    }
}
