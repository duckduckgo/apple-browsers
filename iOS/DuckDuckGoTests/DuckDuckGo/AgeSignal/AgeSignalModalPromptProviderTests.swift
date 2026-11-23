//
//  AgeSignalModalPromptProviderTests.swift
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
final class AgeSignalModalPromptProviderTests: XCTestCase {

    private var storage: (any ThrowingKeyedStoring<AgeSignalSettings>)!
    private var service: AgeRangeServiceMock!
    private let presenter = PresenterViewController()

    override func setUp() async throws {
        try await super.setUp()
        storage = InMemoryKeyValueStore().throwingKeyedStoring()
        service = AgeRangeServiceMock()
    }

    func testItIsAnExternalProvider() {
        XCTAssertEqual(makeProvider().presentationKind, .external)
    }

    func testWhenRequestIsRequiredAndDueThenItBecomesEligible() async {
        let provider = makeProvider()

        await waitUntilEligible(provider)
    }

    func testWhenFlagIsOffThenItIsNotEligibleAndAppleIsNotAsked() {
        let provider = makeProvider(isFlagOn: false)

        XCTAssertFalse(provider.isEligibleToPresent(isOnboardingComplete: true))
        XCTAssertEqual(service.isRequestRequiredCount, 0)
    }

    func testWhenOnboardingIsNotCompleteThenItIsNotEligible() async {
        let provider = makeProvider()
        await waitUntilEligible(provider)

        XCTAssertFalse(provider.isEligibleToPresent(isOnboardingComplete: false))
    }

    func testWhenRequestIsNotRequiredThenItIsNotEligible() async {
        service.isRequired = false
        service.didAnswerIsRequestRequired = expectation(description: "Apple was asked")
        let provider = makeProvider()

        await fulfillment(of: [service.didAnswerIsRequestRequired!], timeout: 1)

        XCTAssertFalse(provider.isEligibleToPresent(isOnboardingComplete: true))
    }

    func testWhenUserAnswersThenItCompletesAsShownAndIsNoLongerEligible() async {
        let provider = makeProvider()
        await waitUntilEligible(provider)

        let result = await presentExternalPrompt(provider, from: presenter)

        guard case .shown(.ageSignal) = result else {
            return XCTFail("Expected .shown(.ageSignal), got \(result)")
        }
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertFalse(provider.isEligibleToPresent(isOnboardingComplete: true))
    }

    func testWhenRequestFailsThenItCompletesAsNotShownAndStaysEligible() async {
        service.requestError = CancellationError()
        let provider = makeProvider()
        await waitUntilEligible(provider)

        let result = await presentExternalPrompt(provider, from: presenter)

        guard case .notShown = result else {
            return XCTFail("Expected .notShown, got \(result)")
        }
        XCTAssertTrue(provider.isEligibleToPresent(isOnboardingComplete: true))
    }

    func testWhenPresenterIsNotAViewControllerThenItCompletesAsNotShownWithoutRequesting() async {
        let provider = makeProvider()
        await waitUntilEligible(provider)

        let result = await presentExternalPrompt(provider, from: MockModalPromptPresenter())

        guard case .notShown = result else {
            return XCTFail("Expected .notShown, got \(result)")
        }
        XCTAssertEqual(service.requestCount, 0)
    }

    // MARK: - Helpers

    private func makeProvider(isFlagOn: Bool = true) -> AgeSignalModalPromptProvider {
        AgeSignalModalPromptProvider(requester: AgeSignalRequester(service: service, storage: storage),
                                     featureFlagger: MockFeatureFlagger(enabledFeatureFlags: isFlagOn ? [.declaredAgeRange] : []))
    }

    private func presentExternalPrompt(_ provider: AgeSignalModalPromptProvider, from presenter: ModalPromptPresenter) async -> ExternalPromptResult {
        await withCheckedContinuation { continuation in
            provider.presentExternalPrompt(from: presenter) { continuation.resume(returning: $0) }
        }
    }

    /// The provider learns Apple's answer asynchronously and exposes no signal for it.
    private func waitUntilEligible(_ provider: AgeSignalModalPromptProvider) async {
        let predicate = NSPredicate { _, _ in
            MainActor.assumeIsolated { provider.isEligibleToPresent(isOnboardingComplete: true) }
        }
        await fulfillment(of: [expectation(for: predicate, evaluatedWith: nil)], timeout: 5)
    }
}

@MainActor
private final class AgeRangeServiceMock: AgeRangeServicing {
    var isRequired = true
    var requestError: Error?
    var didAnswerIsRequestRequired: XCTestExpectation?
    private(set) var isRequestRequiredCount = 0
    private(set) var requestCount = 0

    func isRequestRequired() async throws -> Bool {
        isRequestRequiredCount += 1
        didAnswerIsRequestRequired?.fulfill()
        return isRequired
    }

    func requestAgeRange(in anchor: AgeRangeAnchor) async throws {
        requestCount += 1
        if let requestError {
            throw requestError
        }
    }
}

private final class PresenterViewController: UIViewController, ModalPromptPresenter {}
