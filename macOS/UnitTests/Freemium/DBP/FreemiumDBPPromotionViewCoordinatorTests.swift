//
//  FreemiumDBPPromotionViewCoordinatorTests.swift
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

import XCTest
import Freemium
@testable import DuckDuckGo_Privacy_Browser
import Combine
import Common
import DataBrokerProtection_macOS
import DataBrokerProtectionCore

final class FreemiumDBPPromotionViewCoordinatorTests: XCTestCase {

    private var sut: FreemiumDBPPromotionViewCoordinator!
    private var mockUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockFeature: MockFreemiumDBPFeature!
    private var mockPresenter: MockFreemiumDBPPresenter!
    private let notificationCenter: NotificationCenter = .default
    private var mockPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler!
    private var cancellables: Set<AnyCancellable> = []

    override func setUpWithError() throws {
        mockUserStateManager = MockFreemiumDBPUserStateManager()
        mockFeature = MockFreemiumDBPFeature()
        mockFeature.featureAvailable = true
        mockPresenter = MockFreemiumDBPPresenter()
        mockPixelHandler = MockDataBrokerProtectionFreemiumPixelHandler()

        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter,
            notificationCenter: notificationCenter,
            dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler
        )
    }

    override var allowedNonNilVariables: Set<String> {
        ["notificationCenter"]
    }

    override func tearDownWithError() throws {
        sut = nil
        mockUserStateManager = nil
        mockFeature = nil
        mockPresenter = nil
        mockPixelHandler = nil
        cancellables = []
    }

    func testInitialPromotionVisibility_whenFeatureIsAvailable_andNotDismissed() {
        // Given
        mockUserStateManager.didDismissHomePagePromotion = false
        mockFeature.featureAvailable = true

        // When
        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter
        )

        // Then
        XCTAssertTrue(sut.isHomePagePromotionVisible)
    }

    func testInitialPromotionVisibility_whenPromotionDismissed() {
        // Given
        mockUserStateManager.didDismissHomePagePromotion = true
        mockFeature.featureAvailable = true

        // When
        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter
        )

        // Then
        XCTAssertFalse(sut.isHomePagePromotionVisible)
    }

    @MainActor
    func testProceedAction_dismissesPromotion_callsShowFreemium_andFiresPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.didActivate = false
            sut.isHomePagePromotionVisible = true
        }

        // When
        let viewModel = try XCTUnwrap(sut.viewModel)
        await viewModel.proceedAction()

        // Then
        XCTAssertTrue(mockUserStateManager.didDismissHomePagePromotion)
        XCTAssertTrue(mockPresenter.didCallShowFreemium)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabScanClick)
    }

    @MainActor
    func testCloseAction_dismissesPromotion_andFiresPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.didActivate = false
            mockUserStateManager.firstScanResults = nil
        }

        let viewModel = try XCTUnwrap(sut.viewModel)

        mockPixelHandler.resetCapturedData()

        // When
        viewModel.closeAction()

        // Then
        XCTAssertTrue(mockUserStateManager.didDismissHomePagePromotion)
        XCTAssertTrue(mockPixelHandler.allFiredEvents.contains(DataBrokerProtectionFreemiumPixels.newTabScanDismiss),
                      "Expected newTabScanDismiss to be fired. Actual events: \(mockPixelHandler.allFiredEvents)")
    }

    @MainActor
    func testProceedAction_dismissesResults_callsShowFreemium_andFiresPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.didActivate = false
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 5, brokerCount: 2)
        }

        // When
        let viewModel = try XCTUnwrap(sut.viewModel)
        await viewModel.proceedAction()

        // Then
        XCTAssertTrue(mockUserStateManager.didDismissHomePagePromotion)
        XCTAssertTrue(mockPresenter.didCallShowFreemium)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabResultsClick)
    }

    @MainActor
    func testCloseAction_dismissesResults_andFiresPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 5, brokerCount: 2)
        }

        // When
        let viewModel = try XCTUnwrap(sut.viewModel)
        viewModel.closeAction()

        // Then
        XCTAssertTrue(mockUserStateManager.didDismissHomePagePromotion)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabResultsDismiss)
    }

    @MainActor
    func testProceedAction_dismissesNoResults_callsShowFreemium_andFiresPixel() async throws {
        throw XCTSkip("Flaky")

        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.didActivate = false
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 0, brokerCount: 0)
        }

        // When
        let viewModel = try XCTUnwrap(sut.viewModel)
        await viewModel.proceedAction()

        // Then
        XCTAssertTrue(mockUserStateManager.didDismissHomePagePromotion)
        XCTAssertTrue(mockPresenter.didCallShowFreemium)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabNoResultsClick)
    }

    @MainActor
    func testCloseAction_dismissesNoResults_andFiresPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 0, brokerCount: 0)
        }

        let viewModel = try XCTUnwrap(sut.viewModel)

        mockPixelHandler.resetCapturedData()

        // When
        viewModel.closeAction()

        // Then
        XCTAssertTrue(mockUserStateManager.didDismissHomePagePromotion)
        XCTAssertTrue(mockPixelHandler.allFiredEvents.contains(DataBrokerProtectionFreemiumPixels.newTabNoResultsDismiss),
                      "Expected newTabNoResultsDismiss to be fired. Actual events: \(mockPixelHandler.allFiredEvents)")
    }

    @MainActor
    func testViewModel_whenResultsExist_withMatches() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 5, brokerCount: 2)
        }

        // When
        let viewModel = try await waitForViewModelUpdate()

        // Then
        XCTAssertEqual(viewModel?.description, UserText.homePagePromotionFreemiumDBPPostScanEngagementResultPluralDescription(resultCount: 5, brokerCount: 2))
    }

    @MainActor
    func testViewModel_whenNoResultsExist() async throws {
        // Given
        let viewModel = try await waitForViewModelUpdate {
            mockUserStateManager.firstScanResults = nil
        }

        // Then
        XCTAssertEqual(viewModel?.description, UserText.homePagePromotionFreemiumDBPDescriptionMarkdown)
    }

    @MainActor
    func testViewModel_whenFeatureNotEnabled() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockFeature.featureAvailable = false
        }

        // When
        let viewModel = sut.viewModel

        // Then
        XCTAssertNil(viewModel)
    }

    func testNotificationObservation_updatesPromotionVisibility() {
        // When
        notificationCenter.post(name: .freemiumDBPResultPollingComplete, object: nil)

        // Then
        XCTAssertFalse(mockUserStateManager.didDismissHomePagePromotion)

        // When
        notificationCenter.post(name: .freemiumDBPEntryPointActivated, object: nil)

        // Then
        XCTAssertFalse(mockUserStateManager.didDismissHomePagePromotion)
    }

    func testHomePageBecomesVisible_whenFeatureBecomesAvailable_andDidDismissFalse() {
        // Given
        mockUserStateManager.didDismissHomePagePromotion = false
        mockFeature.featureAvailable = false
        let expectation = XCTestExpectation(description: "isHomePagePromotionVisible becomes true")
        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter
        )
        XCTAssertFalse(sut.isHomePagePromotionVisible)

        // When
        mockFeature.isAvailableSubject.send(true)

        sut.$isHomePagePromotionVisible
            .sink { isVisible in
                if isVisible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)

        // Then
        XCTAssertTrue(sut.isHomePagePromotionVisible)
    }

    func testHomePageBecomesInVisible_whenFeatureBecomesUnAvailable_andDidDismissFalse() {
        // Given
        mockUserStateManager.didDismissHomePagePromotion = false
        mockFeature.featureAvailable = true
        let expectation = XCTestExpectation(description: "isHomePagePromotionVisible becomes true")
        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter
        )
        XCTAssertTrue(sut.isHomePagePromotionVisible)

        // When
        mockFeature.isAvailableSubject.send(false)

        sut.$isHomePagePromotionVisible
            .sink { isVisible in
                if !isVisible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)

        // Then
        XCTAssertFalse(sut.isHomePagePromotionVisible)
    }

    func testHomePageDoesNotBecomeVisible_whenFeatureBecomesAvailable_andDidDismissTrue() {
        // Given
        mockUserStateManager.didDismissHomePagePromotion = true
        mockFeature.featureAvailable = false
        let expectation = XCTestExpectation(description: "isHomePagePromotionVisible becomes true")
        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter
        )
        XCTAssertFalse(sut.isHomePagePromotionVisible)

        // When
        mockFeature.isAvailableSubject.send(true)

        sut.$isHomePagePromotionVisible
            .sink { isVisible in
                if !isVisible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)

        // Then
        XCTAssertFalse(sut.isHomePagePromotionVisible)
    }

    func testHomePageDoesNotBecomeVisible_whenFeatureBecomesUnAvailable_andDidDismissTrue() {
        // Given
        mockUserStateManager.didDismissHomePagePromotion = true
        mockFeature.featureAvailable = true
        let expectation = XCTestExpectation(description: "isHomePagePromotionVisible becomes true")
        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter
        )
        XCTAssertFalse(sut.isHomePagePromotionVisible)

        // When
        mockFeature.isAvailableSubject.send(false)

        sut.$isHomePagePromotionVisible
            .sink { isVisible in
                if !isVisible {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)

        // Then
        XCTAssertFalse(sut.isHomePagePromotionVisible)
    }

    // MARK: - Helpers

    /**
     * Sets up an expectation, then sets up Combine subscription for `sut.$viewModel` that fulfills the expectation,
     * then calls the provided `block`, enables home page promotion and waits for time specified by `duration`
     * before cancelling the subscription.
     */
    @discardableResult @MainActor
    private func waitForViewModelUpdate(for duration: TimeInterval = 1, _ block: () async -> Void = {}) async throws -> PromotionViewModel? {
        let expectation = self.expectation(description: "viewModelUpdate")
        let cancellable = sut.$viewModel.dropFirst().prefix(1).sink { _ in expectation.fulfill() }

        await block()
        sut.isHomePagePromotionVisible = true

        await fulfillment(of: [expectation], timeout: duration)
        cancellable.cancel()

        return sut.viewModel
    }
}

class MockDataBrokerProtectionFreemiumPixelHandler: EventMapping<DataBrokerProtectionFreemiumPixels> {

    var lastFiredEvent: DataBrokerProtectionFreemiumPixels?
    var lastPassedParameters: [String: String]?
    var allFiredEvents: [DataBrokerProtectionFreemiumPixels] = []

    init() {
        var mockMapping: Mapping! = nil

        super.init(mapping: { event, error, params, onComplete in
            // Call the closure after initialization
            mockMapping(event, error, params, onComplete)
        })

        // Now, set the real closure that captures self and stores parameters.
        mockMapping = { [weak self] (event, error, params, onComplete) in
            // Capture the inputs when fire is called
            self?.lastFiredEvent = event
            self?.lastPassedParameters = params
            self?.allFiredEvents.append(event)
        }
    }

    func resetCapturedData() {
        lastFiredEvent = nil
        lastPassedParameters = nil
        allFiredEvents.removeAll()
    }
}
