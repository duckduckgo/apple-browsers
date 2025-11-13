//
//  OnboardingIntroViewModelTests.swift
//  DuckDuckGo
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
import SystemSettingsPiPTutorialTestSupport
import SetDefaultBrowserTestSupport
@testable import DuckDuckGo

@MainActor
final class OnboardingIntroViewModelTests: XCTestCase {
    private var defaultBrowserManagerMock: MockDefaultBrowserManager!
    private var contextualDaxDialogs: ContextualOnboardingLogicMock!
    private var pixelReporterMock: OnboardingPixelReporterMock!
    private var onboardingManagerMock: OnboardingManagerMock!
    private var systemSettingsPiPTutorialManager: MockSystemSettingsPiPTutorialManager!
    private var appIconProvider: (() -> AppIcon)!
    private var addressBarPositionProvider: (() -> AddressBarPosition)!

    override func setUp() {
        super.setUp()
        defaultBrowserManagerMock = MockDefaultBrowserManager()
        contextualDaxDialogs = ContextualOnboardingLogicMock()
        pixelReporterMock = OnboardingPixelReporterMock()
        onboardingManagerMock = OnboardingManagerMock()
        systemSettingsPiPTutorialManager = MockSystemSettingsPiPTutorialManager()
        appIconProvider = { .defaultAppIcon }
        addressBarPositionProvider = { .top }
    }

    override func tearDown() {
        defaultBrowserManagerMock = nil
        contextualDaxDialogs = nil
        pixelReporterMock = nil
        onboardingManagerMock = nil
        systemSettingsPiPTutorialManager = nil
        appIconProvider = nil
        addressBarPositionProvider = nil
        super.tearDown()
    }


    // MARK: - State + Actions

    func testWhenSubscribeToViewStateThenShouldSendLanding() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        let result = sut.state

        // THEN
        XCTAssertEqual(result, .landing)
    }

    func testWhenOnAppearIsCalledThenViewStateChangesToStartOnboardingDialog() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(canSkipTutorial: false), step: .hidden)))
    }

    func testWhenSetDefaultBrowserActionIsCalled_ThenAskPiPManagerToPlayPipForSetDefault_AndMakeNextViewState() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(systemSettingsPiPTutorialManager.didCallPlayPiPTutorialAndNavigateToDestination)
        XCTAssertNil(systemSettingsPiPTutorialManager.capturedDestination)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(systemSettingsPiPTutorialManager.didCallPlayPiPTutorialAndNavigateToDestination)
        XCTAssertEqual(systemSettingsPiPTutorialManager.capturedDestination, .defaultBrowser)
    }

    // MARK: iPhone Flow

    func testWhenSubscribeToViewStateAndIsIphoneFlowThenShouldSendLanding() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT()

        // WHEN
        let result = sut.state

        // THEN
        XCTAssertEqual(result, .landing)
    }

    func testWhenOnAppearIsCalled_AndIsNewUser_AndAndIsIphoneFlow_ThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(canSkipTutorial: false), step: .hidden)))
    }

    func testWhenOnAppearIsCalled_AndIsReturningUser_AndAndIsIphoneFlow_ThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(canSkipTutorial: true), step: .hidden)))
    }

    func testWhenStartOnboardingActionResumingTrueIsCalled_AndIsIphoneFlow_ThenViewStateChangesToBrowsersComparisonDialogAndProgressIs2of4() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)

        // WHEN
        sut.startOnboardingAction(isResumingOnboarding: true)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 4))))
    }

    func testWhenConfirmSkipOnboarding_andIsIphoneFlow_ThenDismissOnboardingAndDisableDaxDialogs() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)
        var didCallDismissOnboarding = false
        sut.onCompletingOnboardingIntro = {
            didCallDismissOnboarding = true
        }
        XCTAssertFalse(contextualDaxDialogs.didCallDisableDaxDialogs)
        XCTAssertFalse(didCallDismissOnboarding)

        // WHEN
        sut.confirmSkipOnboardingAction()

        XCTAssertTrue(contextualDaxDialogs.didCallDisableDaxDialogs)
        XCTAssertTrue(didCallDismissOnboarding)
    }

    func testWhenSetDefaultBrowserActionIsCalledAndIsIphoneFlowThenViewStateChangesToAddToDockPromoDialogAndProgressIs2Of4() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenCancelSetDefaultBrowserActionIsCalledAndIsIphoneFlowThenViewStateChangesToAddToDockPromoDialogAndProgressIs2Of4() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.cancelSetDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenAddtoDockContinueActionIsCalledAndIsIphoneFlowThenThenViewStateChangesToChooseAppIconAndProgressIs3of4() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addToDockPromo)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: false)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 3, totalSteps: 4))))
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIsIphoneFlowThenViewStateChangesToChooseAddressBarPositionDialogAndProgressIs4Of4() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAddressBarPositionDialog, step: .init(currentStep: 4, totalSteps: 4))))
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndIsIphoneFlowThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addressBarPositionSelection)
        sut.onCompletingOnboardingIntro = {
            didCallOnCompletingOnboardingIntro = true
        }
        XCTAssertFalse(didCallOnCompletingOnboardingIntro)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertTrue(didCallOnCompletingOnboardingIntro)
    }

    // MARK: iPad

    func testWhenSubscribeToViewStateAndIsIpadFlowThenShouldSendLanding() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        let sut = makeSUT()

        // WHEN
        let result = sut.state

        // THEN
        XCTAssertEqual(result, .landing)
    }

    func testWhenOnAppearIsCalled_AndIsNewUser_AndAndIsIpadFlow_ThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(canSkipTutorial: false), step: .hidden)))
    }

    func testWhenOnAppearIsCalled_AndIsReturningUser_AndAndIsIpadFlow_ThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(canSkipTutorial: true), step: .hidden)))
    }

    func testWhenStartOnboardingActionResumingTrueIsCalled_AndIsIpadFlow_ThenViewStateChangesToBrowsersComparisonDialogAndProgressIs2of4() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)

        // WHEN
        sut.startOnboardingAction(isResumingOnboarding: true)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 2))))
    }

    func testWhenConfirmSkipOnboarding_andIsIpadFlow_ThenDismissOnboardingAndDisableDaxDialogs() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)
        var didCallDismissOnboarding = false
        sut.onCompletingOnboardingIntro = {
            didCallDismissOnboarding = true
        }
        XCTAssertFalse(contextualDaxDialogs.didCallDisableDaxDialogs)
        XCTAssertFalse(didCallDismissOnboarding)

        // WHEN
        sut.confirmSkipOnboardingAction()

        XCTAssertTrue(contextualDaxDialogs.didCallDisableDaxDialogs)
        XCTAssertTrue(didCallDismissOnboarding)
    }

    func testWhenStartOnboardingActionIsCalledAndIsIpadFlowThenViewStateChangesToBrowsersComparisonDialogAndProgressIs1Of3() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.startOnboardingAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 2))))
    }

    func testWhenSetDefaultBrowserActionIsCalledAndIsIpadFlowThenViewStateChangesToChooseAppIconDialogAndProgressIs2Of3() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 2, totalSteps: 2))))
    }

    func testWhenCancelSetDefaultBrowserActionIsCalledAndIsIpadFlowThenViewStateChangesToChooseAppIconDialogAndProgressIs2Of3() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.cancelSetDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 2, totalSteps: 2))))
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIsIphoneFlowThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)
        sut.onCompletingOnboardingIntro = {
            didCallOnCompletingOnboardingIntro = true
        }
        XCTAssertFalse(didCallOnCompletingOnboardingIntro)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(didCallOnCompletingOnboardingIntro)
    }

    // MARK: - Pixels

    func testWhenOnAppearIsCalledThenPixelReporterMeasureOnboardingIntroImpression() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureOnboardingIntroImpression)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureOnboardingIntroImpression)
    }

    func testWhenStartOnboardingActionIsCalledThenPixelReporterMeasureBrowserComparisonImpression() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureBrowserComparisonImpression)

        // WHEN
        sut.startOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureBrowserComparisonImpression)
    }

    func testWhenSetDefaultBrowserActionThenPixelReporterMeasureChooseBrowserCTAAction() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseBrowserCTAAction)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseBrowserCTAAction)
    }

    func testWhenAppIconScreenPresentedThenPixelReporterMeasureAppIconImpression() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)
        XCTAssertFalse(pixelReporterMock.didCallMeasureBrowserComparisonImpression)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAppIconImpression)
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIconIsCustomColorThenPixelReporterMeasureCustomAppIconColor() {
        // GIVEN
        appIconProvider = { .purple }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIconIsDefaultColorThenPixelReporterDoNotMeasureCustomAppIconColor() {
        // GIVEN
        appIconProvider = { .defaultAppIcon }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)
    }

    func testWhenStateChangesToChooseAddressBarPositionThenPixelReporterMeasureAddressBarSelectionImpression() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddressBarPositionSelectionImpression)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddressBarPositionSelectionImpression)
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndAddressBarPositionIsBottomThenPixelReporterMeasureChooseBottomAddressBarPosition() {
        // GIVEN
        addressBarPositionProvider = { .bottom }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseBottomAddressBarPosition)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseBottomAddressBarPosition)
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndAddressBarPositionIsTopThenPixelReporterDoNotMeasureChooseBottomAddressBarPosition() {
        // GIVEN
        addressBarPositionProvider = { .top }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseBottomAddressBarPosition)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseBottomAddressBarPosition)
    }

    // MARK: - Pixels Skip Onboarding

    func testWhenSkipOnboardingActionIsCalledThenPixelReporterMeasureSkipOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(pixelReporterMock.didCallMeasureSkipOnboardingCTAAction)

        // WHEN
        sut.skipOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureSkipOnboardingCTAAction)
    }

    func testWhenConfirmSkipOnboardingActionIsCalledThenPixelReporterMeasureConfirmSkipOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(pixelReporterMock.didCallMeasureConfirmSkipOnboardingCTAAction)

        // WHEN
        sut.confirmSkipOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureConfirmSkipOnboardingCTAAction)
    }

    func testWhenStartOnboardingActionResumingTrueIsCalledThenPixelReporterMeasureResumeOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(pixelReporterMock.didCallMeasureResumeOnboardingCTAAction)

        // WHEN
        sut.startOnboardingAction(isResumingOnboarding: true)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureResumeOnboardingCTAAction)
    }

    // MARK: - Copy

    func testIntroTitleIsCorrect() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        let result = sut.copy.introTitle

        // THEN
        XCTAssertEqual(result, UserText.Onboarding.Intro.title)
    }

    func testBrowserComparisonTitleIsCorrect() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        let result = sut.copy.browserComparisonTitle

        // THEN
        XCTAssertEqual(result, UserText.Onboarding.BrowsersComparison.title)
    }

    // MARK: - Pixel Add To Dock

    func testWhenStateChangesToAddToDockPromoThenPixelReporterMeasureAddToDockPromoImpression() {
        // GIVEN
        let sut = makeSUT(currentOnboardingStep: .browserComparison)
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockPromoImpression)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockPromoImpression)
    }

    func testWhenAddToDockShowTutorialActionIsCalledThenPixelReporterMeasureAddToDockPromoShowTutorialCTA() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockPromoShowTutorialCTAAction)

        // WHEN
        sut.addToDockShowTutorialAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockPromoShowTutorialCTAAction)
    }

    func testWhenAddToDockContinueActionIsCalledAndIsShowingFromAddToDockTutorialIsTrueThenPixelReporterMeasureAddToDockTutorialDismissCTA() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockTutorialDismissCTAAction)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: true)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockTutorialDismissCTAAction)
    }

    func testWhenAddToDockContinueActionIsCalledAndIsShowingFromAddToDockTutorialIsFalseThenPixelReporterMeasureAddToDockTutorialDismissCTA() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockPromoDismissCTAAction)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: false)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockPromoDismissCTAAction)
    }

    // MARK: - Search Experience Selection

    func testWhenStateChangesToChooseSearchExperienceThenPixelReporterMeasureSearchExperienceSelectionImpression() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addressBarPositionSelection)
        XCTAssertFalse(pixelReporterMock.didCallMeasureSearchExperienceSelectionImpression)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureSearchExperienceSelectionImpression)
    }

    func testWhenSelectSearchExperienceActionIsCalledAndAIChatIsEnabledThenPixelReporterMeasureChooseAIChat() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection, onboardingSearchExperienceProvider: mockSearchExperienceProvider)
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseAIChat)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAIChat)
    }

    func testWhenSelectSearchExperienceActionIsCalledAndAIChatIsDisabledThenPixelReporterMeasureChooseSearchOnly() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection, onboardingSearchExperienceProvider: mockSearchExperienceProvider)
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseSearchOnly)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseSearchOnly)
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndIsIphoneFlowWithSearchExperienceThenViewStateChangesToChooseSearchExperienceDialogAndProgressIs5Of5() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addressBarPositionSelection)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseSearchExperienceDialog, step: .init(currentStep: 5, totalSteps: 5))))
    }

    func testWhenSelectSearchExperienceActionIsCalledAndIsIphoneFlowWithSearchExperienceThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection)
        sut.onCompletingOnboardingIntro = {
            didCallOnCompletingOnboardingIntro = true
        }
        XCTAssertFalse(didCallOnCompletingOnboardingIntro)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(didCallOnCompletingOnboardingIntro)
    }

    // MARK: - iPad Search Experience Selection

    func testWhenAppIconPickerContinueActionIsCalledAndIsIpadFlowWithSearchExperienceThenViewStateChangesToChooseSearchExperienceDialogAndProgressIs3Of3() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseSearchExperienceDialog, step: .init(currentStep: 3, totalSteps: 3))))
    }

    func testWhenStateChangesToChooseSearchExperienceAndIsIpadFlowThenPixelReporterMeasureSearchExperienceSelectionImpression() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)
        XCTAssertFalse(pixelReporterMock.didCallMeasureSearchExperienceSelectionImpression)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureSearchExperienceSelectionImpression)
    }

    func testWhenSelectSearchExperienceActionIsCalledAndAIChatIsEnabledAndIsIpadFlowThenPixelReporterMeasureChooseAIChat() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection, onboardingSearchExperienceProvider: mockSearchExperienceProvider)
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseAIChat)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAIChat)
    }

    func testWhenSelectSearchExperienceActionIsCalledAndAIChatIsDisabledAndIsIpadFlowThenPixelReporterMeasureChooseSearchOnly() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection, onboardingSearchExperienceProvider: mockSearchExperienceProvider)
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseSearchOnly)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseSearchOnly)
    }

    func testWhenSelectSearchExperienceActionIsCalledAndIsIpadFlowWithSearchExperienceThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection)
        sut.onCompletingOnboardingIntro = {
            didCallOnCompletingOnboardingIntro = true
        }
        XCTAssertFalse(didCallOnCompletingOnboardingIntro)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(didCallOnCompletingOnboardingIntro)
    }

}

extension OnboardingIntroViewModelTests {

    func makeSUT(
        currentOnboardingStep: OnboardingIntroStep = .introDialog(isReturningUser: false),
        onboardingSearchExperienceProvider: OnboardingSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
    ) -> OnboardingIntroViewModel {
        OnboardingIntroViewModel(
            defaultBrowserManager: defaultBrowserManagerMock,
            contextualDaxDialogs: contextualDaxDialogs,
            pixelReporter: pixelReporterMock,
            onboardingManager: onboardingManagerMock,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
            currentOnboardingStep: currentOnboardingStep,
            onboardingSearchExperienceProvider: onboardingSearchExperienceProvider,
            appIconProvider: appIconProvider,
            addressBarPositionProvider: addressBarPositionProvider
        )
    }
    
}
