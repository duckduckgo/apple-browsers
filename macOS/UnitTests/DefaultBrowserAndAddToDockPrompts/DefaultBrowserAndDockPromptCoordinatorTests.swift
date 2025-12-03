//
//  DefaultBrowserAndDockPromptCoordinatorTests.swift
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
import BrowserServicesKit
import FeatureFlags
import PixelKitTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptCoordinatorTests: XCTestCase {
    private var promptTypeDeciderMock: MockDefaultBrowserAndDockPromptTypeDecider!
    private var defaultBrowserProviderMock: DefaultBrowserProviderMock!
    private var dockCustomizerMock: DockCustomizerMock!
    private var storeMock: MockDefaultBrowserAndDockPromptStore!
    private var notificationPresenterMock: MockDefaultBrowserAndDockPromptNotificationPresenter!
    private var pixelKitMock: PixelKitMock!
    private var timeTraveller: TimeTraveller!
    private var isOnboardingCompleted = true
    private static let now = Date(timeIntervalSince1970: 1747872000) // 22 May 2025 12:00:00 AM

    override func setUpWithError() throws {
        try super.setUpWithError()

        promptTypeDeciderMock = MockDefaultBrowserAndDockPromptTypeDecider()
        defaultBrowserProviderMock = DefaultBrowserProviderMock()
        dockCustomizerMock = DockCustomizerMock()
        storeMock = MockDefaultBrowserAndDockPromptStore()
        notificationPresenterMock = MockDefaultBrowserAndDockPromptNotificationPresenter()
        timeTraveller = TimeTraveller(date: Self.now)
    }

    override func tearDownWithError() throws {
        promptTypeDeciderMock = nil
        defaultBrowserProviderMock = nil
        dockCustomizerMock = nil
        storeMock = nil
        notificationPresenterMock = nil
        timeTraveller = nil
        pixelKitMock = nil

        try super.tearDownWithError()
    }

    func makeSUT(
        expectedFireCalls: [ExpectedFireCall] = []
    ) -> DefaultBrowserAndDockPromptCoordinator  {
        pixelKitMock = PixelKitMock(expecting: expectedFireCalls)

        return DefaultBrowserAndDockPromptCoordinator(
            promptTypeDecider: promptTypeDeciderMock,
            store: storeMock,
            notificationPresenter: notificationPresenterMock,
            isOnboardingCompleted: { self.isOnboardingCompleted },
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            pixelFiring: pixelKitMock,
            dateProvider: timeTraveller.getDate
        )
    }

    // MARK: - Evaluate prompt eligibility tests

    func testEvaluatePromptEligibility_DefaultBrowserAndAddedToDock_ReturnsNil() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // THEN
        XCTAssertNil(sut.evaluatePromptEligibility)
    }

    func testEvaluatePromptEligibility_DefaultBrowserAndNotAddedToDock_ReturnsAddToDockPrompt() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.evaluatePromptEligibility, .addToDockPrompt)
    }

    func testEvaluatePromptEligibility_NotDefaultBrowserAndAddedToDock_ReturnsSetAsDefaultPrompt() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.evaluatePromptEligibility, .setAsDefaultPrompt)
    }

    func testEvaluatePromptEligibility_NotDefaultBrowserAndNotAddedToDock_ReturnsBothDefaultBrowserAndDockPrompt() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.evaluatePromptEligibility, .bothDefaultBrowserAndDockPrompt)
    }

    // MARK: - Get prompt type tests

    func testGetPromptTypeReturnsNilWhenOnboardingIsNotCompleted() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        isOnboardingCompleted = false
        let sut = makeSUT()

        // THEN
        XCTAssertNil(sut.getPromptType())
    }

    func testGetPromptTypeReturnsValueWhenOnboardingIsNotCompletedAndThenCompletes() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        isOnboardingCompleted = false
        let sut = makeSUT()

        // THEN
        XCTAssertNil(sut.getPromptType())

        // WHEN
        isOnboardingCompleted = true

        // THEN
        XCTAssertNotNil(sut.getPromptType())

    }

    func testGetPromptTypeReturnsNilWhenBrowserIsDefaultAndAddedToDock() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        let sut = makeSUT()

        // THEN
        XCTAssertNil(sut.getPromptType())
    }

    func testGetPromptTypeReturnsPromptWhenBrowserIsNotDefault() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.getPromptType(), .active(.banner))
    }

    func testGetPromptTypeReturnsPromptWhenBrowserIsNotAddedToDock() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.getPromptType(), .active(.banner))
    }

    func testGetPromptTypeSetPopoverSeenWhenPromptReturnedIsPopover() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        promptTypeDeciderMock.promptTypeToReturn = .active(.popover)
        XCTAssertNil(storeMock.popoverShownDate)
        let sut = makeSUT()

        // WHEN
        let result = sut.getPromptType()

        // THEN
        XCTAssertEqual(result, .active(.popover))
        XCTAssertEqual(storeMock.popoverShownDate, Self.now.timeIntervalSince1970)
    }

    func testGetPromptTypeSetInactiveUserModalSeenWhenPromptReturnedIsInactive() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        promptTypeDeciderMock.promptTypeToReturn = .inactive
        XCTAssertNil(storeMock.inactiveUserModalShownDate)
        let sut = makeSUT()

        // WHEN
        let result = sut.getPromptType()

        // THEN
        XCTAssertEqual(result, .inactive)
        XCTAssertEqual(storeMock.inactiveUserModalShownDate, Self.now.timeIntervalSince1970)
    }

    // MARK: - Prompt confirmation tests

    func testConfirmActionCallsAddToDockAndSetAsDefaultBrowserWhenBothDefaultBrowserAndDockPromptType() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        XCTAssertTrue(dockCustomizerMock.dockStatus)
        XCTAssertTrue(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionCallsAddToDockWhenAddToDockPromptType() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        XCTAssertTrue(dockCustomizerMock.dockStatus)
        XCTAssertFalse(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionCallsSetAsDefaultBrowserWhenSetAsDefaultPromptType() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        XCTAssertFalse(dockCustomizerMock.wasAddToDockCalled)
        XCTAssertTrue(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionDoesNothingWhenEvaluatePromptEligibilityIsNil() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        XCTAssertFalse(dockCustomizerMock.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionSetBannerSeen() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertNil(storeMock.inactiveUserModalShownDate)

        // WHEN
        sut.confirmAction(for: .active(.banner))

        // THEN
        XCTAssertEqual(storeMock.bannerShownDate, Self.now.timeIntervalSince1970)
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertNil(storeMock.inactiveUserModalShownDate)
    }

    func testConfirmActionDoesNotSetPopoverSeen() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertNil(storeMock.inactiveUserModalShownDate)

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertNil(storeMock.inactiveUserModalShownDate)
    }

    func testConfirmActionDoesNotSetInactiveUserModalSeen() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertNil(storeMock.inactiveUserModalShownDate)

        // WHEN
        sut.confirmAction(for: .inactive)

        // THEN
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertNil(storeMock.inactiveUserModalShownDate)
    }

    // MARK: - Dismiss Action tests

    func testDismissActionShouldHidePermanentlyFalseSetBannerSeenAndDoesNotSetPermanentlyHiddenFlagToTrue() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: false))

        // THEN
        XCTAssertEqual(storeMock.bannerShownDate, Self.now.timeIntervalSince1970)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)
    }

    func testDismissActionShouldHidePermanentlyTrueSetBannerSeenAndSetPermanentlyHiddenFlagToTrue() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: true))

        // THEN
        XCTAssertEqual(storeMock.bannerShownDate, Self.now.timeIntervalSince1970)
        XCTAssertTrue(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)
    }

    func testDismissActionDoesNotSetPopoverSeen() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.popover), shouldHidePermanently: true))

        // THEN
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)
    }

    func testDismissActionStatusUpdateForBannerPromptSetBannerSeenAndSetPermanentlyHiddenFlagToFalse() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)

        // WHEN
        sut.dismissAction(.statusUpdate(prompt: .active(.banner)))

        // THEN
        XCTAssertEqual(storeMock.bannerShownDate, Self.now.timeIntervalSince1970)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
    }

    func testDismissActionStatusUpdateForPopoverDoesNotSetPopoverSeen() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)

        // WHEN
        sut.dismissAction(.statusUpdate(prompt: .active(.popover)))

        // THEN
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
    }

    func testDismissActionUserInputForInactivePromptTriggersNotification() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(notificationPresenterMock.inactiveUserPromptNotificationShown)

        // WHEN
        sut.dismissAction(.userInput(prompt: .inactive, shouldHidePermanently: false))

        // THEN
        XCTAssertTrue(notificationPresenterMock.inactiveUserPromptNotificationShown)
    }

    func testDismissActionStatusUpdateForInactivePromptDoesNotTriggerNotification() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(notificationPresenterMock.inactiveUserPromptNotificationShown)

        // WHEN
        sut.dismissAction(.statusUpdate(prompt: .inactive))

        // THEN
        XCTAssertFalse(notificationPresenterMock.inactiveUserPromptNotificationShown)
    }

    func testDismissActionsForBannerPromptDoNotTriggerNotification() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(notificationPresenterMock.inactiveUserPromptNotificationShown)

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: false))
        sut.dismissAction(.statusUpdate(prompt: .active(.banner)))

        // THEN
        XCTAssertFalse(notificationPresenterMock.inactiveUserPromptNotificationShown)
    }

    func testDismissActionsForPopoverPromptDoNotTriggerNotification() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(notificationPresenterMock.inactiveUserPromptNotificationShown)

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.popover), shouldHidePermanently: false))
        sut.dismissAction(.statusUpdate(prompt: .active(.popover)))

        // THEN
        XCTAssertFalse(notificationPresenterMock.inactiveUserPromptNotificationShown)
    }

    // MARK: - Popover Pixels

    func testFirePopoverSeenPixelTypeBothWhenPopoverPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .active(.popover)
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverImpression(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverSeenPixelTypeSADOnlyWhenPopoverPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .active(.popover)
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverImpression(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverSeenPixelTypeATTOnlyWhenPopoverPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .active(.popover)
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverImpression(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverConfirmActionTypeBothWhenPopoverConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverConfirmActionTypeSADOnlyWhenPopoverConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverConfirmButtonClicked(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverConfirmActionTypeATTOnlyWhenPopoverConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverConfirmButtonClicked(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .active(.popover))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverDismissActionTypeBothWhenPopoverDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverCloseButtonClicked(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.popover), shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverDismissActionTypeSADOnlyWhenPopoverDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverCloseButtonClicked(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.popover), shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverDismissActionTypeATTOnlyWhenPopoverDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.popoverCloseButtonClicked(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.popover), shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFirePopoverDismissActionUponStatusUpdateThenDoesNotFireDismissPixel() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT(expectedFireCalls: [])

        // WHEN
        sut.dismissAction(.statusUpdate(prompt: .active(.popover)))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - Banner Pixels

    func testFireBannerSeenPixelTypeBothWhenBannerPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        storeMock.bannerShownOccurrences = 6
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerImpression(type: .bothDefaultBrowserAndDockPrompt, numberOfBannersShown: "7"), frequency: .uniqueByNameAndParameters)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerSeenPixelTypeSADOnlyWhenBannerPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        storeMock.bannerShownOccurrences = 9
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerImpression(type: .setAsDefaultPrompt, numberOfBannersShown: "10"), frequency: .uniqueByNameAndParameters)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerSeenPixelTypeATTOnlyWhenBannerPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .active(.banner)
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        storeMock.bannerShownOccurrences = 10
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerImpression(type: .addToDockPrompt, numberOfBannersShown: "10+"), frequency: .uniqueByNameAndParameters)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerConfirmActionTypeBothWhenPopoverConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        storeMock.bannerShownOccurrences = 10
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt, numberOfBannersShown: String(storeMock.bannerShownOccurrences)), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .active(.banner))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerConfirmActionTypeSADOnlyWhenBannerConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        storeMock.bannerShownOccurrences = 4
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerConfirmButtonClicked(type: .setAsDefaultPrompt, numberOfBannersShown: String(storeMock.bannerShownOccurrences)), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .active(.banner))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerConfirmActionTypeATTOnlyWhenBannerConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        storeMock.bannerShownOccurrences = 5
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerConfirmButtonClicked(type: .addToDockPrompt, numberOfBannersShown: String(storeMock.bannerShownOccurrences)), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .active(.banner))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerConfirmActionSendsFixedParameterWhenNumberOfBannerShownIsMoreThanTen() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        storeMock.bannerShownOccurrences = 25
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt, numberOfBannersShown: "10+"), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .active(.banner))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerDismissActionTypeBothWhenBannerDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerCloseButtonClicked(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: false))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testBannerPopoverDismissActionTypeSADOnlyWhenBannerDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerCloseButtonClicked(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: false))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerDismissActionTypeATTOnlyWhenBannerDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerCloseButtonClicked(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: false))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerNeverAskAgainTypeBothWhenBannerDismissActionShouldPermanentlyDismissTrue() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerNeverAskAgainButtonClicked(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerNeverAskAgainTypeSADOnlyWhenBannerDismissActionShouldPermanentlyDismissTrue() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerNeverAskAgainButtonClicked(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerNeverAskAgainTypeATTOnlyWhenBannerDismissActionShouldPermanentlyDismissTrue() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.bannerNeverAskAgainButtonClicked(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .active(.banner), shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireBannerDismissActionUponStatusUpdateThenDoesNotFireDismissPixel() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT(expectedFireCalls: [])

        // WHEN
        sut.dismissAction(.statusUpdate(prompt: .active(.banner)))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - Inactive User Modal Pixels

    func testFireInactiveUserModalSeenPixelTypeBothWhenInactiveUserModalPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .inactive
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalImpression(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalSeenPixelTypeSADOnlyWhenInactiveUserModalPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .inactive
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalImpression(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalSeenPixelTypeATDOnlyWhenInactiveUserModalPromptIsReturned() {
        // GIVEN
        promptTypeDeciderMock.promptTypeToReturn = .inactive
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalImpression(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
         _ = sut.getPromptType()

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalConfirmActionTypeBothWhenInactiveUserModalConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalConfirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .inactive)

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalConfirmActionTypeSADOnlyWheInactiveUserModalConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalConfirmButtonClicked(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .inactive)

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalConfirmActionTypeATDOnlyWhenInactiveUserModalConfirmAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalConfirmButtonClicked(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.confirmAction(for: .inactive)

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalDismissedTypeBothWhenInactiveUserModalDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalDismissed(type: .bothDefaultBrowserAndDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .inactive, shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalDismissedTypeSADOnlyWhenInactiveUserModalDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalDismissed(type: .setAsDefaultPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .inactive, shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalDismissedTypeATDOnlyWhenInactiveUserModalDismissAction() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let expectedPixelCall = ExpectedFireCall(pixel: DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalDismissed(type: .addToDockPrompt), frequency: .standard)
        let sut = makeSUT(expectedFireCalls: [expectedPixelCall])

        // WHEN
        sut.dismissAction(.userInput(prompt: .inactive, shouldHidePermanently: true))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

    func testFireInactiveUserModalDismissedUponStatusUpdateThenDoesNotFireDismissPixel() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT(expectedFireCalls: [])

        // WHEN
        sut.dismissAction(.statusUpdate(prompt: .inactive))

        // THEN
        pixelKitMock.verifyExpectations(file: #file, line: #line)
    }

}
