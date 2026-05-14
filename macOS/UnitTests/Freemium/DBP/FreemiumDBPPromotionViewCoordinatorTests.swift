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

import Combine
import Common
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import Freemium
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FreemiumDBPPromotionViewCoordinatorTests: XCTestCase {

    private var sut: FreemiumDBPPromotionViewCoordinator!
    private var mockUserStateManager: MockFreemiumDBPUserStateManager!
    private var mockFeature: MockFreemiumDBPFeature!
    private var mockPresenter: MockFreemiumDBPPresenter!
    private let notificationCenter: NotificationCenter = .default
    private var mockPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler!
    private var cancellables: Set<AnyCancellable> = []
    private var contextualOnboardingSubject: PassthroughSubject<Bool, Never>!

    override func setUpWithError() throws {
        mockUserStateManager = MockFreemiumDBPUserStateManager()
        mockFeature = MockFreemiumDBPFeature()
        mockFeature.featureAvailable = true
        mockPresenter = MockFreemiumDBPPresenter()
        mockPixelHandler = MockDataBrokerProtectionFreemiumPixelHandler()
        contextualOnboardingSubject = PassthroughSubject<Bool, Never>()

        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter,
            notificationCenter: notificationCenter,
            dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler,
            contextualOnboardingPublisher: contextualOnboardingSubject.eraseToAnyPublisher()
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
        contextualOnboardingSubject = nil
    }

    // MARK: - Raw Eligibility Signals

    func testIsFeatureAvailable_reflectsFeatureState() {
        XCTAssertTrue(sut.isFeatureAvailable)
        mockFeature.isAvailableSubject.send(false)
        let expectation = XCTestExpectation()
        sut.$isFeatureAvailable.dropFirst().sink { available in
            if !available { expectation.fulfill() }
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(sut.isFeatureAvailable)
    }

    // MARK: - refreshViewModel / clearViewModel

    @MainActor
    func testRefreshViewModel_createsViewModel() {
        XCTAssertNil(sut.viewModel)
        sut.refreshViewModel()
        XCTAssertNotNil(sut.viewModel)
    }

    @MainActor
    func testClearViewModel_nilsViewModel() {
        sut.refreshViewModel()
        XCTAssertNotNil(sut.viewModel)
        sut.clearViewModel()
        XCTAssertNil(sut.viewModel)
    }

    // MARK: - onUserAction Callback

    @MainActor
    func testOnUserAction_calledOnProceed() async throws {
        try await waitForViewModelUpdate()

        let expectation = XCTestExpectation(description: "onUserAction called")
        var receivedResult: PromoResult?
        sut.onUserAction = { result in
            receivedResult = result
            expectation.fulfill()
        }

        let viewModel = try XCTUnwrap(sut.viewModel)
        await viewModel.proceedAction()

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedResult, .actioned)
    }

    @MainActor
    func testOnUserAction_calledOnClose() async throws {
        try await waitForViewModelUpdate()

        let expectation = XCTestExpectation(description: "onUserAction called")
        var receivedResult: PromoResult?
        sut.onUserAction = { result in
            receivedResult = result
            expectation.fulfill()
        }

        let viewModel = try XCTUnwrap(sut.viewModel)
        viewModel.closeAction()

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedResult, .ignored())
    }

    // MARK: - Proceed / Close Actions

    @MainActor
    func testProceedAction_callsShowFreemium_andFiresPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.didActivate = false
        }

        // When
        let viewModel = try XCTUnwrap(sut.viewModel)
        await viewModel.proceedAction()

        // Then
        XCTAssertTrue(mockPresenter.didCallShowFreemium)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabScanClick)
    }

    @MainActor
    func testCloseAction_firesPixel() async throws {
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
        XCTAssertTrue(mockPixelHandler.allFiredEvents.contains(DataBrokerProtectionFreemiumPixels.newTabScanDismiss),
                      "Expected newTabScanDismiss to be fired. Actual events: \(mockPixelHandler.allFiredEvents)")
    }

    @MainActor
    func testProceedAction_withResults_callsShowFreemium_andFiresPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.didActivate = false
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 5, brokerCount: 2)
        }

        // When
        let viewModel = try XCTUnwrap(sut.viewModel)
        await viewModel.proceedAction()

        // Then
        XCTAssertTrue(mockPresenter.didCallShowFreemium)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabResultsClick)
    }

    @MainActor
    func testCloseAction_withResults_firesPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 5, brokerCount: 2)
        }

        // When
        let viewModel = try XCTUnwrap(sut.viewModel)
        viewModel.closeAction()

        // Then
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabResultsDismiss)
    }

    @MainActor
    func testProceedAction_withNoResults_callsShowFreemium_andFiresPixel() async throws {
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
        XCTAssertTrue(mockPresenter.didCallShowFreemium)
        XCTAssertEqual(mockPixelHandler.lastFiredEvent, DataBrokerProtectionFreemiumPixels.newTabNoResultsClick)
    }

    @MainActor
    func testCloseAction_withNoResults_firesPixel() async throws {
        // Given
        try await waitForViewModelUpdate {
            mockUserStateManager.firstScanResults = FreemiumDBPMatchResults(matchesCount: 0, brokerCount: 0)
        }

        let viewModel = try XCTUnwrap(sut.viewModel)

        mockPixelHandler.resetCapturedData()

        // When
        viewModel.closeAction()

        // Then
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

    // MARK: - onScanResultsUpdated / hasLegacyDismissal

    func testScanResultsNotification_callsOnScanResultsUpdated() {
        let expectation = XCTestExpectation(description: "onScanResultsUpdated called")
        sut.onScanResultsUpdated = {
            expectation.fulfill()
        }

        notificationCenter.post(name: .freemiumDBPResultPollingComplete, object: nil)

        wait(for: [expectation], timeout: 2.0)
    }

    func testHasLegacyDismissal_readsPersistedFlag() {
        XCTAssertFalse(sut.hasLegacyDismissal)

        mockUserStateManager.didDismissHomePagePromotion = true
        sut = FreemiumDBPPromotionViewCoordinator(
            freemiumDBPUserStateManager: mockUserStateManager,
            freemiumDBPFeature: mockFeature,
            freemiumDBPPresenter: mockPresenter,
            notificationCenter: notificationCenter,
            dataBrokerProtectionFreemiumPixelHandler: mockPixelHandler,
            contextualOnboardingPublisher: contextualOnboardingSubject.eraseToAnyPublisher()
        )

        XCTAssertTrue(sut.hasLegacyDismissal)
    }

    // MARK: - Helpers

    /**
     * Sets up an expectation, then sets up Combine subscription for `sut.$viewModel` that fulfills the expectation,
     * then calls the provided `block`, refreshes the view model and waits for time specified by `duration`
     * before cancelling the subscription.
     */
    @discardableResult @MainActor
    private func waitForViewModelUpdate(for duration: TimeInterval = 5, _ block: () async -> Void = {}) async throws -> PromotionViewModel? {
        let expectation = self.expectation(description: "viewModelUpdate")
        let cancellable = sut.$viewModel.dropFirst().prefix(1).sink { _ in expectation.fulfill() }

        await block()
        sut.refreshViewModel()

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
