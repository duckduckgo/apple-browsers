//
//  DeclaredAgePromoDelegateTests.swift
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

import BrowserServicesKit
import Combine
import FeatureFlags_macOS
@_spi(Testing) import Persistence
import PrivacyConfig
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DeclaredAgePromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var service: DeclaredAgeServiceMock!
    private var storage: (any ThrowingKeyedStoring<DeclaredAgeSettings>)!
    private var reinstallUserDetection: MockReinstallingUserDetecting!
    private var window: NSWindow?

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.declaredAgeRange]
        service = DeclaredAgeServiceMock()
        storage = InMemoryKeyValueStore().throwingKeyedStoring()
        reinstallUserDetection = MockReinstallingUserDetecting()
        window = NSWindow()
    }

    override func tearDown() {
        window = nil
        reinstallUserDetection = nil
        storage = nil
        service = nil
        featureFlagger = nil
        super.tearDown()
    }

    private func makeSUT() -> DeclaredAgePromoDelegate {
        let requester = DeclaredAgeRequester(service: service, storage: storage)
        return DeclaredAgePromoDelegate(requester: requester,
                                        reinstallUserDetection: reinstallUserDetection,
                                        featureFlagger: featureFlagger,
                                        windowProvider: { self.window })
    }

    private func eligibility(of sut: DeclaredAgePromoDelegate, becomes value: Bool) async {
        let eligibilityExpectation = expectation(description: "eligibility is \(value)")
        let cancellable = sut.isEligiblePublisher
            .first(where: { $0 == value })
            .sink { _ in eligibilityExpectation.fulfill() }
        await fulfillment(of: [eligibilityExpectation], timeout: 1)
        cancellable.cancel()
    }

    private func makeEligibleSUT() async -> DeclaredAgePromoDelegate {
        let sut = makeSUT()
        await eligibility(of: sut, becomes: true)
        return sut
    }

    private func show(_ sut: DeclaredAgePromoDelegate) async -> PromoResult {
        await sut.show(history: PromoHistoryRecord(id: "declared-age"), force: false)
    }

    // MARK: - Eligibility

    func testWhenFlagIsOffThenItIsNotEligibleAndAppleIsNotAsked() async {
        featureFlagger.enabledFeatureFlags = []

        let sut = makeSUT()
        // Lets a wrongly started Apple check run before asserting.
        await Task.yield()

        XCTAssertFalse(sut.isEligible)
        XCTAssertEqual(service.isRequestRequiredCount, 0)
    }

    func testWhenRequestIsNotRequiredThenItIsNotEligible() async {
        service.isRequired = false

        let sut = makeSUT()
        await Task.yield()

        XCTAssertEqual(service.isRequestRequiredCount, 1)
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenRequestIsNotRequiredThenTheNextLaunchDoesNotAskApple() async {
        service.isRequired = false
        let firstLaunch = makeSUT()
        await Task.yield()

        let nextLaunch = makeSUT()
        await Task.yield()

        XCTAssertEqual(service.isRequestRequiredCount, 1)
        XCTAssertFalse(firstLaunch.isEligible)
        XCTAssertFalse(nextLaunch.isEligible)
    }

    func testWhenFlagTurnsOnThenItBecomesEligible() async {
        featureFlagger.enabledFeatureFlags = []
        let sut = makeSUT()

        featureFlagger.enabledFeatureFlags = [.declaredAgeRange]
        featureFlagger.triggerUpdate()

        await eligibility(of: sut, becomes: true)
    }

    func testWhenAlreadyAskedAndUserReinstalledThenItBecomesEligibleAgain() async {
        _ = await show(await makeEligibleSUT())

        reinstallUserDetection.isReinstallingUser = true

        await eligibility(of: makeSUT(), becomes: true)
    }

    func testWhenFlagTurnsOffThenEligibilityBecomesFalse() async {
        let sut = await makeEligibleSUT()

        featureFlagger.enabledFeatureFlags = []
        featureFlagger.triggerUpdate()

        await eligibility(of: sut, becomes: false)
    }

    // MARK: - show()

    func testWhenThereIsNoKeyWindowThenShowReturnsNoChangeWithoutRequestingAndStaysEligible() async {
        window = nil
        let sut = await makeEligibleSUT()

        let result = await show(sut)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(service.requestCount, 0)
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenRequestFailsThenShowReturnsNoChangeAndIsNoLongerEligible() async {
        service.requestError = CancellationError()
        let sut = await makeEligibleSUT()

        let result = await show(sut)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertFalse(sut.isEligible)
    }
}

@MainActor
private final class DeclaredAgeServiceMock: DeclaredAgeServicing {
    var isRequired = true
    var requestError: Error?
    private(set) var isRequestRequiredCount = 0
    private(set) var requestCount = 0

    func isRequestRequired() async throws -> Bool {
        isRequestRequiredCount += 1
        return isRequired
    }

    func requestDeclaredAge(in anchor: DeclaredAgeAnchor) async throws -> Bool {
        requestCount += 1
        if let requestError {
            throw requestError
        }
        return true
    }
}
