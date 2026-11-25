//
//  DeclaredAgePromptTests.swift
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
import UIKit
import BrowserServicesKit
import FeatureFlags_iOS
@_spi(Testing) import Persistence
@testable import DuckDuckGo

@MainActor
final class DeclaredAgePromptTests: XCTestCase {

    private var storage: (any ThrowingKeyedStoring<DeclaredAgeSettings>)!
    private var service: DeclaredAgeServiceMock!
    private var featureFlagger: MockFeatureFlagger!
    private let viewController = UIViewController()

    override func setUp() async throws {
        try await super.setUp()
        storage = InMemoryKeyValueStore().throwingKeyedStoring()
        service = DeclaredAgeServiceMock()
        featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.declaredAgeRange])
    }

    func testWhenRequestIsNeededThenItRequestsTheDeclaredAge() async {
        let prompt = await launchAndWaitForRequest()

        XCTAssertEqual(service.requestCount, 1)
        XCTAssertFalse(prompt.presentIfNeeded())
    }

    func testWhenFlagIsOffThenAppleIsNotAsked() async {
        featureFlagger.enabledFeatureFlags = []
        let prompt = makePrompt()

        await mainQueueDrains()

        XCTAssertEqual(service.isRequestRequiredCount, 0)
        XCTAssertFalse(prompt.presentIfNeeded())
    }

    func testWhenFlagTurnsOnThenItRequestsTheDeclaredAge() async {
        featureFlagger.enabledFeatureFlags = []
        let prompt = makePrompt()
        let requested = expectRequest()

        featureFlagger.enabledFeatureFlags = [.declaredAgeRange]
        featureFlagger.triggerUpdate()
        await fulfillment(of: [requested], timeout: 1)

        XCTAssertEqual(service.requestCount, 1)
        XCTAssertFalse(prompt.presentIfNeeded())
    }

    func testWhenThereIsNoAnchorThenTheRequestWaitsForOne() async {
        let prompt = await launchAndWaitForAppleCheck(anchor: nil)
        XCTAssertFalse(prompt.presentIfNeeded())
        let requested = expectRequest()

        prompt.anchorProvider = { self.viewController }

        XCTAssertTrue(prompt.presentIfNeeded())
        await fulfillment(of: [requested], timeout: 1)
        XCTAssertEqual(service.requestCount, 1)
    }

    func testWhenFlagTurnsOffAfterTheCheckThenItDoesNotRequest() async {
        let prompt = await launchAndWaitForAppleCheck(anchor: nil)

        featureFlagger.enabledFeatureFlags = []
        prompt.anchorProvider = { self.viewController }

        XCTAssertFalse(prompt.presentIfNeeded())
        XCTAssertEqual(service.requestCount, 0)
    }

    func testWhenRequestIsNotRequiredThenItDoesNotRequest() async {
        service.isRequired = false

        let prompt = await launchAndWaitForAppleCheck(anchor: viewController)

        XCTAssertFalse(prompt.presentIfNeeded())
        XCTAssertEqual(service.requestCount, 0)
    }

    func testWhenRequestFailsThenItIsNotAttemptedAgainDuringTheSameLaunch() async {
        service.requestError = CancellationError()

        let prompt = await launchAndWaitForRequest()

        XCTAssertFalse(prompt.presentIfNeeded())
        XCTAssertEqual(service.requestCount, 1)
    }

    func testWhenRequestFailsThenTheNextLaunchRetries() async {
        service.requestError = CancellationError()

        _ = await launchAndWaitForRequest()
        _ = await launchAndWaitForRequest()

        XCTAssertEqual(service.requestCount, 2)
    }

    func testWhenUserAlreadyAnsweredThenTheNextLaunchDoesNotAskApple() async {
        _ = await launchAndWaitForRequest()

        let nextLaunchPrompt = makePrompt()
        await mainQueueDrains()

        XCTAssertEqual(service.isRequestRequiredCount, 1)
        XCTAssertFalse(nextLaunchPrompt.presentIfNeeded())
    }

    // MARK: - Helpers

    private func makePrompt(anchor: UIViewController? = UIViewController()) -> DeclaredAgePrompt {
        let prompt = DeclaredAgePrompt(requester: DeclaredAgeRequester(service: service, storage: storage), featureFlagger: featureFlagger)
        prompt.anchorProvider = { anchor }
        return prompt
    }

    private func expectRequest() -> XCTestExpectation {
        let requested = expectation(description: "declared age requested")
        service.onRequest = { requested.fulfill() }
        return requested
    }

    private func launchAndWaitForRequest() async -> DeclaredAgePrompt {
        let requested = expectRequest()
        let prompt = makePrompt()
        await fulfillment(of: [requested], timeout: 1)
        return prompt
    }

    private func launchAndWaitForAppleCheck(anchor: UIViewController?) async -> DeclaredAgePrompt {
        let appleWasAsked = expectation(description: "Apple was asked")
        service.onIsRequestRequired = { appleWasAsked.fulfill() }
        let prompt = makePrompt(anchor: anchor)
        await fulfillment(of: [appleWasAsked], timeout: 1)
        return prompt
    }

    /// The flag subscription hops to the main queue, so anything it was going to start has started once this returns.
    private func mainQueueDrains() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        await Task.yield()
    }
}

@MainActor
private final class DeclaredAgeServiceMock: DeclaredAgeServicing {
    var isRequired = true
    var requestError: Error?
    var onIsRequestRequired: (() -> Void)?
    var onRequest: (() -> Void)?
    private(set) var isRequestRequiredCount = 0
    private(set) var requestCount = 0

    func isRequestRequired() async throws -> Bool {
        isRequestRequiredCount += 1
        onIsRequestRequired?()
        return isRequired
    }

    func requestDeclaredAge(in anchor: DeclaredAgeAnchor) async throws -> Bool {
        requestCount += 1
        onRequest?()
        if let requestError {
            throw requestError
        }
        return true
    }
}
