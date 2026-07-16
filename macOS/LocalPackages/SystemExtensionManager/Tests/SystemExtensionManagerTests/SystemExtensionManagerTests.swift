//
//  SystemExtensionManagerTests.swift
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
import SystemExtensions
@testable import SystemExtensionManager

final class SystemExtensionManagerTests: XCTestCase {

    func testActivationStateWhenNoPropertiesThenNotInstalled() {
        let result = SystemExtensionManager.activationState(from: [])

        XCTAssertEqual(result, .notInstalled)
    }

    func testActivationStateWhenPropertyIsEnabledThenEnabled() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: true, isAwaitingUserApproval: false, isUninstalling: false)
        ])

        XCTAssertEqual(result, .enabled)
    }

    func testActivationStateWhenPropertyIsAwaitingUserApprovalThenAwaitingUserApproval() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: true, isUninstalling: false)
        ])

        XCTAssertEqual(result, .awaitingUserApproval)
    }

    func testActivationStateWhenPropertyIsUninstallingThenUninstalling() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true)
        ])

        XCTAssertEqual(result, .uninstalling)
    }

    func testActivationStateWhenPropertyIsNotEnabledAndNotAwaitingApprovalThenDisabled() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: false)
        ])

        XCTAssertEqual(result, .disabled)
    }

    func testActivationStateWhenMultiplePropertiesIncludeEnabledThenEnabledWins() {
        let result = SystemExtensionManager.activationState(from: [
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true),
            .init(isEnabled: false, isAwaitingUserApproval: true, isUninstalling: false),
            .init(isEnabled: true, isAwaitingUserApproval: false, isUninstalling: false),
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true),
            .init(isEnabled: false, isAwaitingUserApproval: false, isUninstalling: true)
        ])

        XCTAssertEqual(result, .enabled)
    }

    func testSystemSettingsURLStringTargetsNetworkExtensionOnSequoia() throws {
        guard #available(macOS 15, *) else {
            throw XCTSkip("Specific ExtensionsPreferences URL is only used on macOS 15 and above")
        }

        let result = SystemExtensionManager.systemSettingsURLString(
            forExtensionWithIdentifier: "com.duckduckgo.test.extension"
        )

        XCTAssertEqual(
            result,
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.system_extension.network_extension.extension-point&extensionIdentifier=com.duckduckgo.test.extension"
        )
    }

    func testSystemSettingsURLStringEscapesExtensionIdentifier() throws {
        guard #available(macOS 15, *) else {
            throw XCTSkip("Specific ExtensionsPreferences URL is only used on macOS 15 and above")
        }

        let result = SystemExtensionManager.systemSettingsURLString(
            forExtensionWithIdentifier: "com.duckduckgo.test.extension&debug=true"
        )

        XCTAssertTrue(result.contains("extensionIdentifier=com.duckduckgo.test.extension%26debug%3Dtrue"))
    }

    func testRequestTimesOutWhenNoDelegateCallbackIsReceived() async {
        let manager = CapturingSystemExtensionRequestManager()
        let request = SystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.duckduckgo.test.extension",
            manager: manager,
            waitingForUserApproval: nil,
            requestTimeout: 0.01
        )

        do {
            try await request.submit()
            XCTFail("Expected request to time out")
        } catch {
            XCTAssertEqual(error as? SystemExtensionRequestError, .requestTimedOut)
        }

        XCTAssertEqual(manager.submittedRequests.count, 1)
    }

    func testRequestCancellationResumesAwaitingSubmit() async {
        let manager = CapturingSystemExtensionRequestManager()
        let requestSubmitted = expectation(description: "Request submitted")
        manager.onSubmit = { _ in
            requestSubmitted.fulfill()
        }

        let request = SystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.duckduckgo.test.extension",
            manager: manager,
            waitingForUserApproval: nil,
            requestTimeout: 10
        )

        let task = Task {
            try await request.submit()
        }

        await fulfillment(of: [requestSubmitted], timeout: 1)
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected request to be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testActivationStateReturnsUnknownWhenPropertiesRequestTimesOut() async {
        let manager = CapturingSystemExtensionRequestManager()
        let systemExtensionManager = SystemExtensionManager(
            extensionBundleID: "com.duckduckgo.test.extension",
            manager: manager,
            requestTimeout: 0.01
        )

        let result = await systemExtensionManager.activationState()

        XCTAssertEqual(result, .unknown)
        XCTAssertEqual(manager.submittedRequests.count, 1)
    }

    func testActivationStateReturnsUnknownWhenPropertiesRequestIsCancelled() async {
        let manager = CapturingSystemExtensionRequestManager()
        let requestSubmitted = expectation(description: "Request submitted")
        manager.onSubmit = { _ in
            requestSubmitted.fulfill()
        }
        let systemExtensionManager = SystemExtensionManager(
            extensionBundleID: "com.duckduckgo.test.extension",
            manager: manager,
            requestTimeout: 10
        )

        let task = Task {
            await systemExtensionManager.activationState()
        }

        await fulfillment(of: [requestSubmitted], timeout: 1)
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .unknown)
    }
}

private final class CapturingSystemExtensionRequestManager: SystemExtensionRequestManaging {

    var onSubmit: ((OSSystemExtensionRequest) -> Void)?

    var submittedRequests: [OSSystemExtensionRequest] {
        lock.lock()
        defer { lock.unlock() }

        return _submittedRequests
    }

    private let lock = NSLock()
    private var _submittedRequests: [OSSystemExtensionRequest] = []

    func submitRequest(_ request: OSSystemExtensionRequest) {
        lock.lock()
        _submittedRequests.append(request)
        lock.unlock()

        onSubmit?(request)
    }
}
