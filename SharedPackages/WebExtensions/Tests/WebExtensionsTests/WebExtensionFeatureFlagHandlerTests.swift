//
//  WebExtensionFeatureFlagHandlerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
import WebKit
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionFeatureFlagHandlerTests: XCTestCase {

    private var mockWebExtensionManager: MockWebExtensionManaging!
    private var featureFlagSubject: PassthroughSubject<Bool, Never>!
    private var embeddedFlagSubject: PassthroughSubject<Bool, Never>!
    private var sut: WebExtensionFeatureFlagHandler!

    override func setUp() {
        super.setUp()
        mockWebExtensionManager = MockWebExtensionManaging()
        featureFlagSubject = PassthroughSubject<Bool, Never>()
        embeddedFlagSubject = PassthroughSubject<Bool, Never>()
    }

    override func tearDown() {
        sut = nil
        featureFlagSubject = nil
        embeddedFlagSubject = nil
        mockWebExtensionManager = nil
        super.tearDown()
    }

    func testWhenFeatureFlagDisabledThenUninstallAllExtensionsIsCalled() async throws {
        let callbackExpectation = expectation(description: "onFeatureFlagDisabled called")
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackExpectation.fulfill() }
        )

        featureFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertTrue(mockWebExtensionManager.uninstallAllExtensionsCalled)
    }

    func testWhenFeatureFlagEnabledThenUninstallAllExtensionsIsNotCalled() async throws {
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackCalled = true }
        )

        featureFlagSubject.send(true)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(mockWebExtensionManager.uninstallAllExtensionsCalled)
        XCTAssertFalse(callbackCalled)
    }

    func testWhenPublisherIsNilThenHandlerDoesNotCrash() {
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: nil,
            onFeatureFlagDisabled: { callbackCalled = true }
        )

        XCTAssertFalse(mockWebExtensionManager.uninstallAllExtensionsCalled)
        XCTAssertFalse(callbackCalled)
    }

    func testWhenWebExtensionManagerProviderReturnsNilThenCallbackIsStillCalled() async throws {
        let callbackExpectation = expectation(description: "onFeatureFlagDisabled called")
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { nil },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackExpectation.fulfill() }
        )

        featureFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        await fulfillment(of: [callbackExpectation], timeout: 1.0)
    }

    func testWhenFeatureFlagToggledMultipleTimesThenOnlyDisableTriggersUninstall() async throws {
        let disabledExpectation = expectation(description: "onFeatureFlagDisabled called twice")
        disabledExpectation.expectedFulfillmentCount = 2
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { disabledExpectation.fulfill() }
        )

        featureFlagSubject.send(true)
        featureFlagSubject.send(true)
        featureFlagSubject.send(false)
        featureFlagSubject.send(true)
        featureFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        await fulfillment(of: [disabledExpectation], timeout: 1.0)
    }

    // MARK: - Feature Flag Enabled Tests

    func testWhenFeatureFlagEnabledThenOnFeatureFlagEnabledCallbackIsCalled() async throws {
        let expectation = expectation(description: "onFeatureFlagEnabled called")
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagEnabled: {
                expectation.fulfill()
            },
            onFeatureFlagDisabled: {}
        )

        featureFlagSubject.send(true)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testWhenFeatureFlagDisabledThenOnFeatureFlagEnabledCallbackIsNotCalled() async throws {
        var enabledCallbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagEnabled: {
                enabledCallbackCalled = true
            },
            onFeatureFlagDisabled: {}
        )

        featureFlagSubject.send(false)

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(enabledCallbackCalled)
    }

    func testWhenFeatureFlagToggledMultipleTimesThenBothCallbacksAreCalled() async throws {
        var enabledCount = 0
        var disabledCount = 0

        let firstEnabled = expectation(description: "first onFeatureFlagEnabled")
        let secondEnabled = expectation(description: "second onFeatureFlagEnabled")

        let firstDisabled = expectation(description: "first onFeatureFlagDisabled")
        let secondDisabled = expectation(description: "second onFeatureFlagDisabled")

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagEnabled: {
                enabledCount += 1
                if enabledCount == 1 {
                    firstEnabled.fulfill()
                } else {
                    secondEnabled.fulfill()
                }
            },
            onFeatureFlagDisabled: {
                disabledCount += 1
                if disabledCount == 1 {
                    firstDisabled.fulfill()
                } else {
                    secondDisabled.fulfill()
                }
            }
        )

        featureFlagSubject.send(true)
        await fulfillment(of: [firstEnabled], timeout: 1.0)

        featureFlagSubject.send(false)
        await fulfillment(of: [firstDisabled], timeout: 1.0)

        featureFlagSubject.send(true)
        await fulfillment(of: [secondEnabled], timeout: 1.0)

        featureFlagSubject.send(false)
        await fulfillment(of: [secondDisabled], timeout: 1.0)

        XCTAssertEqual(enabledCount, 2)
        XCTAssertEqual(disabledCount, 2)
    }

    // MARK: - Embedded Extension Flag Tests

    func testWhenEmbeddedFlagDisabledThenUninstallEmbeddedExtensionIsCalled() async throws {
        let uninstallExpectation = expectation(description: "uninstallEmbeddedExtension called")
        mockWebExtensionManager.uninstallEmbeddedExtensionHandler = {
            uninstallExpectation.fulfill()
        }
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: {}
        )

        embeddedFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        await fulfillment(of: [uninstallExpectation], timeout: 1.0)
        XCTAssertEqual(mockWebExtensionManager.uninstalledEmbeddedType, .embedded)
    }

    func testWhenEmbeddedFlagEnabledThenUninstallEmbeddedExtensionIsNotCalled() async throws {
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: {}
        )

        embeddedFlagSubject.send(true)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(mockWebExtensionManager.uninstallEmbeddedExtensionCalled)
    }

    func testWhenEmbeddedFlagDisabledThenOnlyEmbeddedExtensionIsUninstalled() async throws {
        let uninstallExpectation = expectation(description: "uninstallEmbeddedExtension called")
        mockWebExtensionManager.uninstallEmbeddedExtensionHandler = {
            uninstallExpectation.fulfill()
        }
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackCalled = true }
        )

        embeddedFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        await fulfillment(of: [uninstallExpectation], timeout: 1.0)
        XCTAssertFalse(mockWebExtensionManager.uninstallAllExtensionsCalled)
        XCTAssertFalse(callbackCalled)
    }

    // MARK: - Embedded Extension Flag Enabled Tests

    func testWhenEmbeddedFlagEnabledThenOnEmbeddedExtensionFlagEnabledCallbackIsCalled() async throws {
        let expectation = expectation(description: "onEmbeddedExtensionFlagEnabled called")
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: {},
            onEmbeddedExtensionFlagEnabled: {
                expectation.fulfill()
            }
        )

        embeddedFlagSubject.send(true)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testWhenEmbeddedFlagDisabledThenOnEmbeddedExtensionFlagEnabledCallbackIsNotCalled() async throws {
        var enabledCallbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: {},
            onEmbeddedExtensionFlagEnabled: {
                enabledCallbackCalled = true
            }
        )

        embeddedFlagSubject.send(false)

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(enabledCallbackCalled)
    }

    func testWhenEmbeddedFlagToggledMultipleTimesThenBothCallbacksAreCalled() async throws {
        var enabledCount = 0
        var disabledCount = 0

        let firstEnabled = expectation(description: "first onEmbeddedExtensionFlagEnabled")
        let secondEnabled = expectation(description: "second onEmbeddedExtensionFlagEnabled")

        let firstDisabled = expectation(description: "first embedded disabled")
        let secondDisabled = expectation(description: "second embedded disabled")

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: {},
            onEmbeddedExtensionFlagEnabled: {
                enabledCount += 1
                if enabledCount == 1 {
                    firstEnabled.fulfill()
                } else {
                    secondEnabled.fulfill()
                }
            }
        )

        mockWebExtensionManager.uninstallEmbeddedExtensionHandler = {
            disabledCount += 1
            if disabledCount == 1 {
                firstDisabled.fulfill()
            } else {
                secondDisabled.fulfill()
            }
        }

        embeddedFlagSubject.send(true)
        await fulfillment(of: [firstEnabled], timeout: 1.0)

        embeddedFlagSubject.send(false)
        await fulfillment(of: [firstDisabled], timeout: 1.0)

        embeddedFlagSubject.send(true)
        await fulfillment(of: [secondEnabled], timeout: 1.0)

        embeddedFlagSubject.send(false)
        await fulfillment(of: [secondDisabled], timeout: 1.0)

        XCTAssertEqual(enabledCount, 2)
        XCTAssertEqual(disabledCount, 2)
    }

    // MARK: - Race Condition Prevention Tests

    func testWhenWebExtensionsFlagRapidlyToggledEnabledThenDisabledThenEnableCallbackDoesNotRunAfterDisable() async throws {
        var disabledCallbackExecuted = false
        var enabledCallbackExecutedAfterDisabled = false

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagEnabled: {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                if disabledCallbackExecuted {
                    enabledCallbackExecutedAfterDisabled = true
                }
            },
            onFeatureFlagDisabled: {
                disabledCallbackExecuted = true
            }
        )

        featureFlagSubject.send(true)
        featureFlagSubject.send(false)

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(disabledCallbackExecuted)
        XCTAssertFalse(enabledCallbackExecutedAfterDisabled)
    }

    func testWhenEmbeddedFlagRapidlyToggledEnabledThenDisabledThenEnableCallbackDoesNotRunAfterDisable() async throws {
        var disabledCallbackExecuted = false
        var enabledCallbackExecutedAfterDisabled = false

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: {},
            onEmbeddedExtensionFlagEnabled: {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                if disabledCallbackExecuted {
                    enabledCallbackExecutedAfterDisabled = true
                }
            }
        )

        mockWebExtensionManager.uninstallEmbeddedExtensionHandler = {
            disabledCallbackExecuted = true
        }

        embeddedFlagSubject.send(true)
        embeddedFlagSubject.send(false)

        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(disabledCallbackExecuted)
        XCTAssertFalse(enabledCallbackExecutedAfterDisabled)
    }

    func testWhenWebExtensionsFlagToggledEnabledDisabledEnabledThenOnlyLastEnableRuns() async throws {
        var enabledCallCount = 0
        let enabledExpectation = expectation(description: "onFeatureFlagEnabled called once")

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagEnabled: {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                enabledCallCount += 1
                enabledExpectation.fulfill()
            },
            onFeatureFlagDisabled: {}
        )

        featureFlagSubject.send(true)
        featureFlagSubject.send(false)
        featureFlagSubject.send(true)

        await fulfillment(of: [enabledExpectation], timeout: 1.0)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(enabledCallCount, 1)
    }

    func testWhenEmbeddedFlagToggledEnabledDisabledEnabledThenOnlyLastEnableRuns() async throws {
        var enabledCallCount = 0
        let enabledExpectation = expectation(description: "onEmbeddedExtensionFlagEnabled called once")

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: {},
            onEmbeddedExtensionFlagEnabled: {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                enabledCallCount += 1
                enabledExpectation.fulfill()
            }
        )

        embeddedFlagSubject.send(true)
        embeddedFlagSubject.send(false)
        embeddedFlagSubject.send(true)

        await fulfillment(of: [enabledExpectation], timeout: 1.0)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(enabledCallCount, 1)
    }
}

// MARK: - Mock

@available(macOS 15.4, iOS 18.4, *)
private final class MockWebExtensionManaging: WebExtensionManaging {

    var uninstallAllExtensionsCalled = false
    var uninstallEmbeddedExtensionCalled = false
    var uninstalledEmbeddedType: DuckDuckGoWebExtensionType?
    var uninstallEmbeddedExtensionHandler: (() -> Void)?
    var syncEmbeddedExtensionsCalled = false

    var loadedExtensions: Set<WKWebExtensionContext> { [] }
    var webExtensionIdentifiers: [String] { [] }
    var controller: WKWebExtensionController { WKWebExtensionController() }
    var eventsListener: WebExtensionEventsListening { MockEventsListener() }
    var extensionUpdates: AsyncStream<Void> { AsyncStream { _ in } }

    func loadInstalledExtensions() async {}
    func installExtension(from sourceURL: URL) async throws {}
    func uninstallExtension(identifier: String) throws {}

    @discardableResult
    func uninstallAllExtensions() -> [Result<Void, Error>] {
        uninstallAllExtensionsCalled = true
        return []
    }

    @MainActor
    func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {
        syncEmbeddedExtensionsCalled = true
    }

    func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {
        uninstallEmbeddedExtensionCalled = true
        uninstalledEmbeddedType = type
        uninstallEmbeddedExtensionHandler?()
    }

    func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? {
        nil
    }

    func unloadAllExtensions() {}

    func extensionName(for identifier: String) -> String? { nil }
    func extensionVersion(for identifier: String) -> String? { nil }
    func extensionContext(for url: URL) -> WKWebExtensionContext? { nil }
    func context(for identifier: String) -> WKWebExtensionContext? { nil }
}

@available(macOS 15.4, iOS 18.4, *)
private final class MockEventsListener: WebExtensionEventsListening {
    var controller: WKWebExtensionController?

    func didOpenWindow(_ window: WKWebExtensionWindow) {}
    func didCloseWindow(_ window: WKWebExtensionWindow) {}
    func didFocusWindow(_ window: WKWebExtensionWindow) {}
    func didOpenTab(_ tab: WKWebExtensionTab) {}
    func didCloseTab(_ tab: WKWebExtensionTab, windowIsClosing: Bool) {}
    func didActivateTab(_ tab: WKWebExtensionTab, previousActiveTab: WKWebExtensionTab?) {}
    func didSelectTabs(_ tabs: [WKWebExtensionTab]) {}
    func didDeselectTabs(_ tabs: [WKWebExtensionTab]) {}
    func didMoveTab(_ tab: WKWebExtensionTab, from oldIndex: Int, in oldWindow: WKWebExtensionWindow) {}
    func didReplaceTab(_ oldTab: WKWebExtensionTab, with tab: WKWebExtensionTab) {}
    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tab: WKWebExtensionTab) {}
}
