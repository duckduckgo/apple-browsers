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
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserAndDockPromptCoordinatorTests: XCTestCase {
    private var promptTypeDeciderMock: MockDefaultBrowserAndDockPromptTypeDecider!
    private var defaultBrowserProviderMock: DefaultBrowserProviderMock!
    private var dockCustomizerMock: DockCustomizerMock!
    private var applicationBuildTypeMock: ApplicationBuildTypeMock!
    private var storeMock: MockDefaultBrowserAndDockPromptStore!
    private var timeTraveller: TimeTraveller!
    private static let now = Date(timeIntervalSince1970: 1747872000) // 22 May 2025 12:00:00 AM

    override func setUpWithError() throws {
        try super.setUpWithError()

        promptTypeDeciderMock = MockDefaultBrowserAndDockPromptTypeDecider()
        defaultBrowserProviderMock = DefaultBrowserProviderMock()
        dockCustomizerMock = DockCustomizerMock()
        applicationBuildTypeMock = ApplicationBuildTypeMock()
        storeMock = MockDefaultBrowserAndDockPromptStore()
        timeTraveller = TimeTraveller(date: Self.now)
    }

    override func tearDownWithError() throws {
        promptTypeDeciderMock = nil
        defaultBrowserProviderMock = nil
        dockCustomizerMock = nil
        applicationBuildTypeMock = nil
        storeMock = nil
        timeTraveller = nil

        try super.tearDownWithError()
    }

    func makeSUT(isOnboardingCompleted: Bool = true) -> DefaultBrowserAndDockPromptCoordinator  {
        DefaultBrowserAndDockPromptCoordinator(
            promptTypeDecider: promptTypeDeciderMock,
            store: storeMock,
            isOnboardingCompleted: isOnboardingCompleted,
            dockCustomization: dockCustomizerMock,
            defaultBrowserProvider: defaultBrowserProviderMock,
            applicationBuildType: applicationBuildTypeMock,
            dateProvider: timeTraveller.getDate
        )
    }

    // MARK: - Evaluate prompt eligibility tests

    func testEvaluatePromptEligibility_SparkleBuild_DefaultBrowserAndAddedToDock_ReturnsNil() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // THEN
        XCTAssertNil(sut.evaluatePromptEligibility)
    }

    func testEvaluatePromptEligibility_SparkleBuild_DefaultBrowserAndNotAddedToDock_ReturnsAddToDockPrompt() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.evaluatePromptEligibility, .addToDockPrompt)
    }

    func testEvaluatePromptEligibility_SparkleBuild_NotDefaultBrowserAndAddedToDock_ReturnsSetAsDefaultPrompt() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.evaluatePromptEligibility, .setAsDefaultPrompt)
    }

    func testEvaluatePromptEligibility_SparkleBuild_NotDefaultBrowserAndNotAddedToDock_ReturnsBothDefaultBrowserAndDockPrompt() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.evaluatePromptEligibility, .bothDefaultBrowserAndDockPrompt)
    }

    func testEvaluatePromptEligibility_AppStoreBuild_DefaultBrowser_ReturnsNil() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = false
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // THEN
        XCTAssertNil(sut.evaluatePromptEligibility)
    }

    func testEvaluatePromptEligibility_AppStoreBuild_NotDefaultBrowser_ReturnsSetAsDefaultPrompt() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = false
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.evaluatePromptEligibility, .setAsDefaultPrompt)
    }

    // MARK: - Get prompt type tests

    func testGetPromptTypeReturnsNilWhenOnboardingIsNotCompleted() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        promptTypeDeciderMock.promptTypeToReturn = .banner
        let sut = makeSUT(isOnboardingCompleted: false)

        // THEN
        XCTAssertNil(sut.getPromptType())
    }

    func testGetPromptTypeReturnsNilWhenBrowserIsDefaultAndAddedToDock() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true
        promptTypeDeciderMock.promptTypeToReturn = .banner
        let sut = makeSUT()

        // THEN
        XCTAssertNil(sut.getPromptType())
    }

    func testGetPromptTypeReturnsPromptWhenBrowserIsNotDefault() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        promptTypeDeciderMock.promptTypeToReturn = .banner
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.getPromptType(), .banner)
    }

    func testGetPromptTypeReturnsPromptWhenBrowserIsNotAddedToDock() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        applicationBuildTypeMock.isSparkleBuild = true
        promptTypeDeciderMock.promptTypeToReturn = .banner
        let sut = makeSUT()

        // THEN
        XCTAssertEqual(sut.getPromptType(), .banner)
    }

    func testGetPromptTypeSetPopoverSeenWhenPromptReturnedIsPopover() {
        // GIVEN
        defaultBrowserProviderMock.isDefault = false
        promptTypeDeciderMock.promptTypeToReturn = .popover
        XCTAssertNil(storeMock.popoverShownDate)
        let sut = makeSUT()

        // WHEN
        let result = sut.getPromptType()

        // THEN
        XCTAssertEqual(result, .popover)
        XCTAssertEqual(storeMock.popoverShownDate, Self.now.timeIntervalSince1970)
    }

    // MARK: - Prompt confirmation tests

    func testConfirmActionCallsAddToDockAndSetAsDefaultBrowserWhenBothDefaultBrowserAndDockPromptType() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .popover)

        // THEN
        XCTAssertTrue(dockCustomizerMock.dockStatus)
        XCTAssertTrue(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionCallsAddToDockWhenAddToDockPromptType() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .popover)

        // THEN
        XCTAssertTrue(dockCustomizerMock.dockStatus)
        XCTAssertFalse(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionCallsSetAsDefaultBrowserWhenSetAsDefaultPromptType() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .popover)

        // THEN
        XCTAssertFalse(dockCustomizerMock.wasAddToDockCalled)
        XCTAssertTrue(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionDoesNothingWhenEvaluatePromptEligibilityIsNil() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = true
        dockCustomizerMock.dockStatus = true
        let sut = makeSUT()

        // WHEN
        sut.confirmAction(for: .popover)

        // THEN
        XCTAssertFalse(dockCustomizerMock.wasAddToDockCalled)
        XCTAssertFalse(defaultBrowserProviderMock.wasPresentDefaultBrowserPromptCalled)
    }

    func testConfirmActionSetBannerSeen() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.confirmAction(for: .banner)

        // THEN
        XCTAssertEqual(storeMock.bannerShownDate, Self.now.timeIntervalSince1970)
        XCTAssertNil(storeMock.popoverShownDate)
    }

    func testConfirmActionDoesNotSetPopoverSeen() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.confirmAction(for: .popover)

        // THEN
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertNil(storeMock.popoverShownDate)
    }

    // MARK: - Dismiss Action tests

    func testDismissActionShouldHidePermanentlyFalseSetBannerSeenAndDoesNotSetPermanentlyHiddenFlagToTrue() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.dismissAction(.userInput(prompt: .banner, shouldHidePermanently: false))

        // THEN
        XCTAssertEqual(storeMock.bannerShownDate, Self.now.timeIntervalSince1970)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)
    }

    func testDismissActionShouldHidePermanentlyTrueSetBannerSeenAndSetPermanentlyHiddenFlagToTrue() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.dismissAction(.userInput(prompt: .banner, shouldHidePermanently: true))

        // THEN
        XCTAssertEqual(storeMock.bannerShownDate, Self.now.timeIntervalSince1970)
        XCTAssertTrue(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)
    }

    func testDismissActionDoesNotSetPopoverSeen() {
        // GIVEN
        applicationBuildTypeMock.isSparkleBuild = true
        defaultBrowserProviderMock.isDefault = false
        dockCustomizerMock.dockStatus = false
        let sut = makeSUT()
        XCTAssertNil(storeMock.bannerShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
        XCTAssertNil(storeMock.popoverShownDate)

        // WHEN
        sut.dismissAction(.userInput(prompt: .popover, shouldHidePermanently: true))

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
        sut.dismissAction(.statusUpdate(prompt: .banner))

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
        sut.dismissAction(.statusUpdate(prompt: .popover))

        // THEN
        XCTAssertNil(storeMock.popoverShownDate)
        XCTAssertFalse(storeMock.isBannerPermanentlyDismissed)
    }
}

final class FeatureFlaggerMock: FeatureFlagger {
    var internalUserDecider: InternalUserDecider
    var localOverrides: FeatureFlagLocalOverriding?

    var mockActiveExperiments: [String: ExperimentData] = [:]

    var enabledFeatureFlags: [FeatureFlag] = []

    var cohortToReturn: (any FeatureFlagCohortDescribing)?

    public init(internalUserDecider: InternalUserDecider = DefaultInternalUserDecider(store: MockInternalUserStoring()),
                enabledFeatureFlags: [FeatureFlag] = []) {
        self.internalUserDecider = internalUserDecider
        self.enabledFeatureFlags = enabledFeatureFlags
    }

    func isFeatureOn<Flag: FeatureFlagDescribing>(for featureFlag: Flag, allowOverride: Bool) -> Bool {
        guard let flag = featureFlag as? FeatureFlag else {
            return false
        }
        guard enabledFeatureFlags.contains(flag) else {
            return false
        }
        return true
    }

    func getCohortIfEnabled(_ subfeature: any PrivacySubfeature) -> CohortID? {
        return nil
    }

    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        if isFeatureOn(for: featureFlag, allowOverride: false) {
            return cohortToReturn
        } else {
            return nil
        }
    }

    var allActiveExperiments: Experiments {
        mockActiveExperiments
    }
}
