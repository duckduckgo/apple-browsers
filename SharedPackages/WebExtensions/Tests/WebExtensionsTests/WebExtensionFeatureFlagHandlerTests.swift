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
    private var sut: WebExtensionFeatureFlagHandler!

    override func setUp() {
        super.setUp()
        mockWebExtensionManager = MockWebExtensionManaging()
        featureFlagSubject = PassthroughSubject<Bool, Never>()
    }

    override func tearDown() {
        sut = nil
        featureFlagSubject = nil
        mockWebExtensionManager = nil
        super.tearDown()
    }

    func testWhenFeatureFlagDisabledThenUninstallAllExtensionsIsCalled() {
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManager: mockWebExtensionManager,
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackCalled = true }
        )

        featureFlagSubject.send(false)

        XCTAssertTrue(mockWebExtensionManager.uninstallAllExtensionsCalled)
        XCTAssertTrue(callbackCalled)
    }

    func testWhenFeatureFlagEnabledThenUninstallAllExtensionsIsNotCalled() {
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManager: mockWebExtensionManager,
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackCalled = true }
        )

        featureFlagSubject.send(true)

        XCTAssertFalse(mockWebExtensionManager.uninstallAllExtensionsCalled)
        XCTAssertFalse(callbackCalled)
    }

    func testWhenPublisherIsNilThenHandlerDoesNotCrash() {
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManager: mockWebExtensionManager,
            featureFlagPublisher: nil,
            onFeatureFlagDisabled: { callbackCalled = true }
        )

        XCTAssertFalse(mockWebExtensionManager.uninstallAllExtensionsCalled)
        XCTAssertFalse(callbackCalled)
    }

    func testWhenWebExtensionManagerIsNilThenCallbackIsStillCalled() {
        var callbackCalled = false
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManager: nil,
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackCalled = true }
        )

        featureFlagSubject.send(false)

        XCTAssertTrue(callbackCalled)
    }

    func testWhenFeatureFlagToggledMultipleTimesThenOnlyDisableTriggersUninstall() {
        var callbackCount = 0
        sut = WebExtensionFeatureFlagHandler(
            webExtensionManager: mockWebExtensionManager,
            featureFlagPublisher: featureFlagSubject.eraseToAnyPublisher(),
            onFeatureFlagDisabled: { callbackCount += 1 }
        )

        featureFlagSubject.send(true)
        featureFlagSubject.send(true)
        featureFlagSubject.send(false)
        featureFlagSubject.send(true)
        featureFlagSubject.send(false)

        XCTAssertEqual(callbackCount, 2)
    }
}

// MARK: - Mock

@available(macOS 15.4, iOS 18.4, *)
private final class MockWebExtensionManaging: WebExtensionManaging {

    var uninstallAllExtensionsCalled = false

    var hasInstalledExtensions: Bool { false }
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

    func extensionName(for identifier: String) -> String? { nil }
    func extensionContext(for url: URL) -> WKWebExtensionContext? { nil }
    func context(for identifier: String) -> WKWebExtensionContext? { nil }
}

@available(macOS 15.4, iOS 18.4, *)
private final class MockEventsListener: WebExtensionEventsListening {
    var controller: WKWebExtensionController?
    func navigatedToURL(_ url: URL, for identifier: String) {}
}
