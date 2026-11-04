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
import WebExtensionsTestSupport

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionFeatureFlagHandlerTests: XCTestCase {

    private var mockWebExtensionManager: MockWebExtensionManaging!
    private var embeddedFlagSubject: PassthroughSubject<Bool, Never>!
    private var adBlockingDefaultsFlagSubject: PassthroughSubject<Bool, Never>!
    private var sut: WebExtensionFeatureFlagHandler!

    override func setUp() {
        super.setUp()
        mockWebExtensionManager = MockWebExtensionManaging()
        embeddedFlagSubject = PassthroughSubject<Bool, Never>()
        adBlockingDefaultsFlagSubject = PassthroughSubject<Bool, Never>()
    }

    override func tearDown() {
        sut = nil
        embeddedFlagSubject = nil
        adBlockingDefaultsFlagSubject = nil
        mockWebExtensionManager = nil
        super.tearDown()
    }

    // MARK: - Embedded Extension Flag Tests

    func testWhenEmbeddedFlagDisabledThenUninstallEmbeddedExtensionIsCalled() async throws {
        let uninstallExpectation = expectation(description: "uninstallEmbeddedExtension called")
        mockWebExtensionManager.uninstallEmbeddedExtensionHandler = {
            uninstallExpectation.fulfill()
        }
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher()
        )

        embeddedFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        await fulfillment(of: [uninstallExpectation], timeout: 1.0)
        XCTAssertEqual(mockWebExtensionManager.uninstalledEmbeddedType, .embedded)
    }

    func testWhenEmbeddedFlagEnabledThenUninstallEmbeddedExtensionIsNotCalled() async throws {
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher()
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
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher()
        )

        embeddedFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        await fulfillment(of: [uninstallExpectation], timeout: 1.0)
        XCTAssertFalse(mockWebExtensionManager.uninstallAllExtensionsCalled)
    }

    // MARK: - Embedded Extension Flag Enabled Tests

    func testWhenEmbeddedFlagEnabledThenOnEmbeddedExtensionFlagEnabledCallbackIsCalled() async throws {
        let expectation = expectation(description: "onEmbeddedExtensionFlagEnabled called")
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
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
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
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
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
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

    func testWhenEmbeddedFlagRapidlyToggledEnabledThenDisabledThenEnableCallbackDoesNotRunAfterDisable() async throws {
        var disabledCallbackExecuted = false
        var enabledCallbackExecutedAfterDisabled = false

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
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

    func testWhenEmbeddedFlagToggledEnabledDisabledEnabledThenOnlyLastEnableRuns() async throws {
        var enabledCallCount = 0
        let enabledExpectation = expectation(description: "onEmbeddedExtensionFlagEnabled called once")

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            embeddedExtensionFlagPublisher: embeddedFlagSubject.eraseToAnyPublisher(),
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

    // MARK: - Ad Blocking Defaults Flag Tests

    func testWhenAdBlockingDefaultsFlagFlipsToTrueThenChangeCallbackIsCalled() async throws {
        let changedExpectation = expectation(description: "onAdBlockingDefaultsFlagChanged called")
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            adBlockingDefaultsFlagPublisher: adBlockingDefaultsFlagSubject.eraseToAnyPublisher(),
            onAdBlockingDefaultsFlagChanged: { changedExpectation.fulfill() }
        )

        adBlockingDefaultsFlagSubject.send(true)

        await fulfillment(of: [changedExpectation], timeout: 1.0)
    }

    func testWhenAdBlockingDefaultsFlagFlipsToFalseThenChangeCallbackIsCalled() async throws {
        let changedExpectation = expectation(description: "onAdBlockingDefaultsFlagChanged called")
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            adBlockingDefaultsFlagPublisher: adBlockingDefaultsFlagSubject.eraseToAnyPublisher(),
            onAdBlockingDefaultsFlagChanged: { changedExpectation.fulfill() }
        )

        adBlockingDefaultsFlagSubject.send(false)

        await fulfillment(of: [changedExpectation], timeout: 1.0)
    }

    func testWhenAdBlockingDefaultsFlagFlipsThenWebExtensionManagerIsNotUninstalled() async throws {
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            adBlockingDefaultsFlagPublisher: adBlockingDefaultsFlagSubject.eraseToAnyPublisher(),
            onAdBlockingDefaultsFlagChanged: {}
        )

        adBlockingDefaultsFlagSubject.send(true)
        adBlockingDefaultsFlagSubject.send(false)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(mockWebExtensionManager.uninstallAllExtensionsCalled)
        XCTAssertFalse(mockWebExtensionManager.uninstallEmbeddedExtensionCalled)
    }

    func testWhenAdBlockingDefaultsPublisherIsNilThenHandlerDoesNotCrash() {
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            adBlockingDefaultsFlagPublisher: nil,
            onAdBlockingDefaultsFlagChanged: { callbackCalled = true }
        )

        XCTAssertFalse(callbackCalled)
    }

    func testWhenAdBlockingDefaultsCallbackIsNilThenHandlerDoesNotCrashOnEmission() async throws {
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            adBlockingDefaultsFlagPublisher: adBlockingDefaultsFlagSubject.eraseToAnyPublisher(),
            onAdBlockingDefaultsFlagChanged: nil
        )

        adBlockingDefaultsFlagSubject.send(true)
        try await Task.sleep(for: .milliseconds(100))
    }

    func testWhenAdBlockingDefaultsFlagToggledMultipleTimesThenCallbackIsCalledForEachEmission() async throws {
        var callCount = 0
        let firstCall = expectation(description: "first onAdBlockingDefaultsFlagChanged")
        let secondCall = expectation(description: "second onAdBlockingDefaultsFlagChanged")

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            adBlockingDefaultsFlagPublisher: adBlockingDefaultsFlagSubject.eraseToAnyPublisher(),
            onAdBlockingDefaultsFlagChanged: {
                callCount += 1
                if callCount == 1 {
                    firstCall.fulfill()
                } else {
                    secondCall.fulfill()
                }
            }
        )

        adBlockingDefaultsFlagSubject.send(true)
        await fulfillment(of: [firstCall], timeout: 1.0)

        adBlockingDefaultsFlagSubject.send(false)
        await fulfillment(of: [secondCall], timeout: 1.0)

        XCTAssertEqual(callCount, 2)
    }

    func testWhenAdBlockingDefaultsFlagRapidlyFlippedThenOnlyLastCallbackRuns() async throws {
        var callCount = 0
        let lastCallExpectation = expectation(description: "last onAdBlockingDefaultsFlagChanged completes")

        sut = WebExtensionFeatureFlagHandler(
            webExtensionManagerProvider: { [weak self] in self?.mockWebExtensionManager },
            adBlockingDefaultsFlagPublisher: adBlockingDefaultsFlagSubject.eraseToAnyPublisher(),
            onAdBlockingDefaultsFlagChanged: {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                callCount += 1
                lastCallExpectation.fulfill()
            }
        )

        adBlockingDefaultsFlagSubject.send(true)
        adBlockingDefaultsFlagSubject.send(false)
        adBlockingDefaultsFlagSubject.send(true)

        await fulfillment(of: [lastCallExpectation], timeout: 1.0)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(callCount, 1)
    }
}
