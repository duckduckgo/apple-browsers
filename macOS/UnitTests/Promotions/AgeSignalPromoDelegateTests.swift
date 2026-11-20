//
//  AgeSignalPromoDelegateTests.swift
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
final class AgeSignalPromoDelegateTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var service: AgeRangeServiceMock!
    private var windowControllersManager: WindowControllersManagerMock!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.declaredAgeRange]
        service = AgeRangeServiceMock()
        windowControllersManager = WindowControllersManagerMock()
    }

    override func tearDown() {
        windowControllersManager.mainWindowControllers = []
        windowControllersManager = nil
        service = nil
        featureFlagger = nil
        super.tearDown()
    }

    private func makeSUT() -> AgeSignalPromoDelegate {
        let requester = AgeSignalRequester(service: service, storage: InMemoryKeyValueStore().throwingKeyedStoring())
        return AgeSignalPromoDelegate(requester: requester,
                                      reinstallUserDetection: MockReinstallingUserDetecting(),
                                      featureFlagger: featureFlagger,
                                      windowControllersManager: windowControllersManager)
    }

    private func eligibility(of sut: AgeSignalPromoDelegate, becomes value: Bool) async {
        let eligibilityExpectation = expectation(description: "eligibility is \(value)")
        let cancellable = sut.isEligiblePublisher
            .first(where: { $0 == value })
            .sink { _ in eligibilityExpectation.fulfill() }
        await fulfillment(of: [eligibilityExpectation], timeout: 1)
        cancellable.cancel()
    }

    private func makeEligibleSUT() async -> AgeSignalPromoDelegate {
        let sut = makeSUT()
        await eligibility(of: sut, becomes: true)
        return sut
    }

    private func addKeyWindow() {
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [Tab]()),
                                                            windowControllersManager: WindowControllersManagerMock())
        let mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: MockFeatureFlagger())
        )
        let window = MockWindow(isVisible: false)
        let windowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            fireViewModel: Application.appDelegate.fireCoordinator.fireViewModel,
            themeManager: MockThemeManager()
        )
        windowController.window = window
        windowControllersManager.mainWindowControllers = [windowController]
    }

    private func show(_ sut: AgeSignalPromoDelegate) async -> PromoResult {
        await sut.show(history: PromoHistoryRecord(id: "age-signal"), force: false)
    }

    // MARK: - Eligibility

    func testWhenFlagIsOffThenItIsNotEligibleAndAppleIsNotAsked() {
        featureFlagger.enabledFeatureFlags = []

        let sut = makeSUT()

        XCTAssertFalse(sut.isEligible)
        XCTAssertEqual(service.isRequestRequiredCount, 0)
    }

    func testWhenRequestIsRequiredAndDueThenItBecomesEligible() async {
        let sut = await makeEligibleSUT()

        XCTAssertTrue(sut.isEligible)
    }

    func testWhenRequestIsNotRequiredThenItIsNotEligible() async {
        service.isRequired = false
        let askedExpectation = expectation(description: "Apple asked")
        service.onIsRequestRequired = { askedExpectation.fulfill() }

        let sut = makeSUT()
        await fulfillment(of: [askedExpectation], timeout: 1)

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFlagTurnsOffThenEligibilityBecomesFalse() async {
        let sut = await makeEligibleSUT()

        featureFlagger.enabledFeatureFlags = []
        featureFlagger.triggerUpdate()

        await eligibility(of: sut, becomes: false)
    }

    // MARK: - show()

    func testWhenThereIsNoKeyWindowThenShowReturnsNoChangeWithoutRequesting() async {
        let sut = await makeEligibleSUT()

        let result = await show(sut)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testWhenRequestSucceedsThenShowIsIgnoredAndNoLongerEligible() async {
        addKeyWindow()
        let sut = await makeEligibleSUT()

        let result = await show(sut)

        XCTAssertEqual(result, .ignored(cooldown: 0))
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertFalse(sut.isEligible)
    }

    func testWhenRequestFailsThenShowReturnsNoChangeAndStaysEligible() async {
        addKeyWindow()
        service.requestError = CancellationError()
        let sut = await makeEligibleSUT()

        let result = await show(sut)

        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(sut.isEligible)
    }

    // MARK: - hide()

    func testHideBeforeShowingDoesNothing() {
        let sut = makeSUT()

        sut.hide()
        sut.hide()
    }
}

@MainActor
private final class AgeRangeServiceMock: AgeRangeServicing {
    var isRequired = true
    var requestError: Error?
    var onIsRequestRequired: (() -> Void)?
    private(set) var isRequestRequiredCount = 0
    private(set) var requestCount = 0

    func isRequestRequired() async throws -> Bool {
        isRequestRequiredCount += 1
        onIsRequestRequired?()
        return isRequired
    }

    func requestAgeRange(in anchor: AgeRangeAnchor) async throws {
        requestCount += 1
        if let requestError {
            throw requestError
        }
    }
}
