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

import Core
import PersistenceTestingUtils
import PrivacyConfig
import SetDefaultBrowserTestSupport
import SystemSettingsPiPTutorialTestSupport
import XCTest

@testable import DuckDuckGo

@MainActor
final class OnboardingIntroViewModelTests: XCTestCase {
    private var defaultBrowserManagerMock: MockDefaultBrowserManager!
    private var contextualDaxDialogs: ContextualOnboardingLogicMock!
    private var pixelReporterMock: OnboardingPixelReporterMock!
    private var onboardingManagerMock: OnboardingManagerMock!
    private var systemSettingsPiPTutorialManager: MockSystemSettingsPiPTutorialManager!
    private var tutorialSettingsMock: MockTutorialSettings!
    private var appIconProvider: (() -> AppIcon)!
    private var addressBarPositionProvider: (() -> AddressBarPosition)!

    override func setUp() {
        super.setUp()
        defaultBrowserManagerMock = MockDefaultBrowserManager()
        contextualDaxDialogs = ContextualOnboardingLogicMock()
        pixelReporterMock = OnboardingPixelReporterMock()
        onboardingManagerMock = OnboardingManagerMock()
        systemSettingsPiPTutorialManager = MockSystemSettingsPiPTutorialManager()
        tutorialSettingsMock = MockTutorialSettings(hasSeenOnboarding: false)
        appIconProvider = { .defaultAppIcon }
        addressBarPositionProvider = { .top }
    }

    override func tearDown() {
        defaultBrowserManagerMock = nil
        contextualDaxDialogs = nil
        pixelReporterMock = nil
        onboardingManagerMock = nil
        systemSettingsPiPTutorialManager = nil
        tutorialSettingsMock = nil
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
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .default), step: .hidden)))
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

    func testWhenRestoreActionProvided_PerformRestoreInvokesAction_AndDefersContextualDaxDialogsDismissal() {
        // GIVEN
        let restorePromptHandlerMock = MockRestorePromptHandler()
        let sut = makeSUT(
            currentOnboardingStep: .introDialog(isReturningUser: true),
            restorePromptHandler: restorePromptHandlerMock
        )
        XCTAssertFalse(restorePromptHandlerMock.didCallRestoreSyncAccount)
        XCTAssertFalse(contextualDaxDialogs.didCallDisableDaxDialogs)

        // WHEN
        sut.restoreSyncAccountAction()

        // THEN
        XCTAssertTrue(restorePromptHandlerMock.didCallRestoreSyncAccount)
        XCTAssertFalse(contextualDaxDialogs.didCallDisableDaxDialogs)
    }

    func testWhenRestoreActionProvided_AndOnboardingCompletes_ThenDisablesContextualDaxDialogs() {
        // GIVEN
        let restorePromptHandlerMock = MockRestorePromptHandler()
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let sut = makeSUT(
            currentOnboardingStep: .searchExperienceSelection,
            restorePromptHandler: restorePromptHandlerMock
        )
        sut.restoreSyncAccountAction()
        XCTAssertFalse(contextualDaxDialogs.didCallDisableDaxDialogs)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(contextualDaxDialogs.didCallDisableDaxDialogs)
    }

    func testWhenOnboardingCompletes_AndRestoreActionNotInvoked_ThenDoesNotDisableContextualDaxDialogs() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addressBarPositionSelection)
        XCTAssertFalse(contextualDaxDialogs.didCallDisableDaxDialogs)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertFalse(contextualDaxDialogs.didCallDisableDaxDialogs)
    }

    func testWhenReturningUserAndRestorePromptEligibilityIsTrueThenShowsRestorePrompt() {
        // GIVEN
        let restorePromptHandlerMock = MockRestorePromptHandler()
        restorePromptHandlerMock.isEligibleForRestorePromptValue = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let sut = makeSUT(
            currentOnboardingStep: .introDialog(isReturningUser: true),
            restorePromptHandler: restorePromptHandlerMock
        )

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .restoreData), step: .hidden)))
    }

    func testWhenReturningUserAndRestorePromptEligibilityIsFalseThenDoesNotShowRestorePrompt() {
        // GIVEN
        let restorePromptHandlerMock = MockRestorePromptHandler()
        restorePromptHandlerMock.isEligibleForRestorePromptValue = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let sut = makeSUT(
            currentOnboardingStep: .introDialog(isReturningUser: true),
            restorePromptHandler: restorePromptHandlerMock
        )

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .skipTutorial), step: .hidden)))
    }

    func testWhenUserIsNotReturningAndRestorePromptEligibilityIsTrueThenDoesNotShowRestorePrompt() {
        // GIVEN
        let restorePromptHandlerMock = MockRestorePromptHandler()
        restorePromptHandlerMock.isEligibleForRestorePromptValue = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(
            currentOnboardingStep: .introDialog(isReturningUser: false),
            restorePromptHandler: restorePromptHandlerMock
        )

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .default), step: .hidden)))
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
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .default), step: .hidden)))
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
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .skipTutorial), step: .hidden)))
    }

    func testWhenStartOnboardingActionResumingTrueIsCalled_AndIsIphoneFlow_ThenViewStateChangesToBrowsersComparisonDialogAndProgressIs1of5() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)

        // WHEN
        sut.startOnboardingAction(isResumingOnboarding: true)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 5))))
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

    func testWhenSetDefaultBrowserActionIsCalledAndIsIphoneFlowThenViewStateChangesToAddToDockPromoDialogAndProgressIs2Of5() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 5))))
    }

    func testWhenCancelSetDefaultBrowserActionIsCalledAndIsIphoneFlowThenViewStateChangesToAddToDockPromoDialogAndProgressIs2Of5() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.cancelSetDefaultBrowserAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureSetDefaultBrowserSkipped)
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 5))))
    }

    func testWhenAddtoDockContinueActionIsCalledAndIsIphoneFlowThenThenViewStateChangesToChooseAppIconAndProgressIs3of5() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addToDockPromo)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: false)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 3, totalSteps: 5))))
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIsIphoneFlowThenViewStateChangesToChooseAddressBarPositionDialogAndProgressIs4Of5() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAddressBarPositionDialog, step: .init(currentStep: 4, totalSteps: 5))))
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndIsIphoneFlowThenViewStateChangesToChooseSearchExperienceDialogAndProgressIs5Of5() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addressBarPositionSelection)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseSearchExperienceDialog, step: .init(currentStep: 5, totalSteps: 5))))
    }

    func testWhenSelectSearchExperienceDialogActionIsCalledAndIsIphoneFlowThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
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
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .default), step: .hidden)))
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
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog(type: .skipTutorial), step: .hidden)))
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
        XCTAssertTrue(pixelReporterMock.didCallMeasureSetDefaultBrowserSkipped)
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

    func testWhenAppIconPickerContinueActionIsCalledAndIconIsCustomColorThenPixelReporterMeasureAppIconColor() {
        // GIVEN
        appIconProvider = { .purple }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseAppIconColor)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAppIconColor)
        XCTAssertEqual(pixelReporterMock.didCaptureAppIconColorSelection, .purple)
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIconIsDefaultColorThenPixelReporterMeasureAppIconColor() {
        // GIVEN
        appIconProvider = { .defaultAppIcon }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseAppIconColor)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAppIconColor)
        XCTAssertEqual(pixelReporterMock.didCaptureAppIconColorSelection, .red)
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

    func testWhenSelectAddressBarPositionActionIsCalledAndAddressBarPositionIsBottomThenPixelReporterMeasureChooseAddressBarPosition() {
        // GIVEN
        addressBarPositionProvider = { .bottom }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseAddressBarPosition)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAddressBarPosition)
        XCTAssertEqual(pixelReporterMock.didCaptureAddressBarPositionSelection, .bottom)
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndAddressBarPositionIsTopThenPixelReporterMeasureChooseAddressBarPosition() {
        // GIVEN
        addressBarPositionProvider = { .top }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseAddressBarPosition)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAddressBarPosition)
        XCTAssertEqual(pixelReporterMock.didCaptureAddressBarPositionSelection, .top)
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

    func testWhenConfirmSkipOnboardingActionIsCalledThenAIChatSearchInputChoiceIsStoredAsEnabled() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true), onboardingSearchExperienceProvider: mockSearchExperienceProvider)
        XCTAssertFalse(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        
        // WHEN
        sut.confirmSkipOnboardingAction()
        
        // THEN
        XCTAssertTrue(mockSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoiceCalled)
        XCTAssertEqual(mockSearchExperienceProvider.lastStoredValue, true)
    }

    func testWhenConfirmSkipOnboardingActionIsCalledThenHasSkippedOnboardingIsSetToTrue() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(tutorialSettingsMock.hasSkippedOnboarding)

        // WHEN
        sut.confirmSkipOnboardingAction()

        // THEN
        XCTAssertTrue(tutorialSettingsMock.hasSkippedOnboarding)
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

    func testWhenStartOnboardingActionResumingFalseIsCalledThenPixelReporterMeasureStartOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: false))
        XCTAssertFalse(pixelReporterMock.didCallMeasureStartOnboardingCTAAction)

        // WHEN
        sut.startOnboardingAction(isResumingOnboarding: false)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureStartOnboardingCTAAction)
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
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
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
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
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
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection, onboardingSearchExperienceProvider: mockSearchExperienceProvider)
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseSearchOnly)

        // WHEN
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseSearchOnly)
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndIsIphoneFlowWithSearchExperienceThenViewStateChangesToChooseSearchExperienceDialogAndProgressIs5Of5() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addressBarPositionSelection)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseSearchExperienceDialog, step: .init(currentStep: 5, totalSteps: 5))))
    }

    func testWhenSelectSearchExperienceActionIsCalledAndIsIphoneFlowWithSearchExperienceThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
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

    // MARK: - Duck.ai Query Experiment Tests

    func testWhenFeatureFlagIsOffThenSelectingAIChatDoesNotInsertExperimentStep() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let featureFlagger = MockFeatureFlagger() // experiment flag not enabled
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection,
                          onboardingSearchExperienceProvider: mockSearchExperienceProvider,
                          featureFlagger: featureFlagger)
        var didComplete = false
        sut.onCompletingOnboardingIntro = { didComplete = true }

        // WHEN
        sut.onAppear()
        sut.selectSearchExperienceAction()

        // THEN: no experiment step inserted → onboarding completes
        XCTAssertTrue(didComplete)
        XCTAssertFalse(sut.state == .onboarding(.init(type: .duckAIQueryExperimentDialog(defaultMode: .duckAI), step: .hidden)))
    }

    func testWhenCohortIsControlThenSelectingAIChatDoesNotInsertExperimentStep() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIQueryExperiment])
        featureFlagger.cohortToReturn = FeatureFlag.DuckAIQueryExperimentCohort.control
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection,
                          onboardingSearchExperienceProvider: mockSearchExperienceProvider,
                          featureFlagger: featureFlagger)
        var didComplete = false
        sut.onCompletingOnboardingIntro = { didComplete = true }

        // WHEN
        sut.onAppear()
        sut.selectSearchExperienceAction()

        // THEN: control cohort → no experiment step → onboarding completes
        XCTAssertTrue(didComplete)
    }

    func testWhenCohortIsTreatmentAThenSelectingAIChatInsertsExperimentStep() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIQueryExperiment])
        featureFlagger.cohortToReturn = FeatureFlag.DuckAIQueryExperimentCohort.treatmentA
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection,
                          onboardingSearchExperienceProvider: mockSearchExperienceProvider,
                          featureFlagger: featureFlagger)

        // WHEN
        sut.onAppear()
        sut.selectSearchExperienceAction()

        // THEN: treatmentA → experiment step inserted, state transitions to it with .duckAI default
        if case .onboarding(let intro) = sut.state,
           case .duckAIQueryExperimentDialog(let mode) = intro.type {
            XCTAssertEqual(mode, .duckAI)
        } else {
            XCTFail("Expected duckAIQueryExperimentDialog state with .duckAI default mode, got \(sut.state)")
        }
    }

    func testWhenCohortIsTreatmentBThenSelectingAIChatInsertsExperimentStep() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIQueryExperiment])
        featureFlagger.cohortToReturn = FeatureFlag.DuckAIQueryExperimentCohort.treatmentB
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection,
                          onboardingSearchExperienceProvider: mockSearchExperienceProvider,
                          featureFlagger: featureFlagger)

        // WHEN
        sut.onAppear()
        sut.selectSearchExperienceAction()

        // THEN: treatmentB → experiment step inserted, default mode is .search
        if case .onboarding(let intro) = sut.state,
           case .duckAIQueryExperimentDialog(let mode) = intro.type {
            XCTAssertEqual(mode, .search)
        } else {
            XCTFail("Expected duckAIQueryExperimentDialog state with .search default mode, got \(sut.state)")
        }
    }

    func testWhenSelectingSearchOnlyThenExperimentStepIsNotInserted() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = false
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIQueryExperiment])
        featureFlagger.cohortToReturn = FeatureFlag.DuckAIQueryExperimentCohort.treatmentA
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection,
                          onboardingSearchExperienceProvider: mockSearchExperienceProvider,
                          featureFlagger: featureFlagger)
        var didComplete = false
        sut.onCompletingOnboardingIntro = { didComplete = true }

        // WHEN
        sut.onAppear()
        sut.selectSearchExperienceAction()

        // THEN: search-only → no experiment step → onboarding completes
        XCTAssertTrue(didComplete)
    }

    // MARK: Pixels

    func testWhenSelectDuckAIQueryExperimentChooseDuckAIThenCorrectPixelFires() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = [.duckAIQuerySelection]
        let sut = makeSUT(currentOnboardingStep: .duckAIQuerySelection)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDuckAIQueryExperimentChooseAIChat)

        // WHEN
        sut.selectDuckAIQueryExperimentAction(selection: .duckAI)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureDuckAIQueryExperimentChooseAIChat)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDuckAIQueryExperimentChooseSearchOnly)
    }

    func testWhenSelectDuckAIQueryExperimentChooseSearchThenCorrectPixelFires() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = [.duckAIQuerySelection]
        let sut = makeSUT(currentOnboardingStep: .duckAIQuerySelection)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDuckAIQueryExperimentChooseSearchOnly)

        // WHEN
        sut.selectDuckAIQueryExperimentAction(selection: .search)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureDuckAIQueryExperimentChooseSearchOnly)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDuckAIQueryExperimentChooseAIChat)
    }

    func testWhenStateChangesToDuckAIQueryExperimentDialogThenImpressionPixelFires() {
        // GIVEN
        let mockSearchExperienceProvider = MockOnboardingSearchExperienceProvider()
        mockSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadStepsWithSearchExperience(isReturningUser: false)
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.onboardingDuckAIQueryExperiment])
        featureFlagger.cohortToReturn = FeatureFlag.DuckAIQueryExperimentCohort.treatmentA
        let sut = makeSUT(currentOnboardingStep: .searchExperienceSelection,
                          onboardingSearchExperienceProvider: mockSearchExperienceProvider,
                          featureFlagger: featureFlagger)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDuckAIQueryExperimentSelectionImpression)

        // WHEN
        sut.onAppear()
        sut.selectSearchExperienceAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureDuckAIQueryExperimentSelectionImpression)
    }

}

// MARK: - Onboarding resume step persistence and restoration

extension OnboardingIntroViewModelTests {

    // Helpers to read/write the resume step directly on the raw store,
    // avoiding parameterised-existential type inference issues on iOS 15 targets.
    private func resumeStepRawValue(in store: MockKeyValueStore) -> String? {
        store.object(forKey: OnboardingStorageKeys.resumeStep.rawValue) as? String
    }

    private func setResumeStep(_ step: OnboardingResumeStep, in store: MockKeyValueStore) {
        store.set(step.rawValue, forKey: OnboardingStorageKeys.resumeStep.rawValue)
    }

    // MARK: Persist

    func testWhenAdvancingToBrowserComparisonThenResumeStepIsPersisted() {
        let store = MockKeyValueStore()
        let sut = makeSUT(resumeStepStore: store)
        sut.onAppear()
        sut.startOnboardingAction()
        XCTAssertEqual(resumeStepRawValue(in: store), OnboardingResumeStep.browserComparison.rawValue)
    }

    func testWhenAdvancingToAddToDockPromoThenResumeStepIsPersisted() {
        let store = MockKeyValueStore()
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison, resumeStepStore: store)
        sut.onAppear()
        sut.setDefaultBrowserAction()
        XCTAssertEqual(resumeStepRawValue(in: store), OnboardingResumeStep.addToDockPromo.rawValue)
    }

    func testWhenAdvancingToAppIconSelectionThenResumeStepIsPersisted() {
        let store = MockKeyValueStore()
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addToDockPromo, resumeStepStore: store)
        sut.onAppear()
        sut.addToDockContinueAction(isShowingAddToDockTutorial: false)
        XCTAssertEqual(resumeStepRawValue(in: store), OnboardingResumeStep.appIconSelection.rawValue)
    }

    func testWhenAdvancingToAddressBarPositionSelectionThenResumeStepIsPersisted() {
        let store = MockKeyValueStore()
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection, resumeStepStore: store)
        sut.onAppear()
        sut.appIconPickerContinueAction()
        XCTAssertEqual(resumeStepRawValue(in: store), OnboardingResumeStep.addressBarPositionSelection.rawValue)
    }

    func testWhenAdvancingToSearchExperienceSelectionThenResumeStepIsPersisted() {
        let store = MockKeyValueStore()
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(currentOnboardingStep: .addressBarPositionSelection, resumeStepStore: store)
        sut.onAppear()
        sut.selectAddressBarPositionAction()
        XCTAssertEqual(resumeStepRawValue(in: store), OnboardingResumeStep.searchExperienceSelection.rawValue)
    }

    // MARK: Restore

    func testWhenResumeStepIsBrowserComparisonThenOnAppearShowsBrowserComparison() {
        let store = MockKeyValueStore()
        setResumeStep(.browserComparison, in: store)
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(resumeStepStore: store)
        sut.onAppear()
        XCTAssertEqual(sut.state.intro?.type, .browsersComparisonDialog)
    }

    func testWhenResumeStepIsAddToDockPromoThenOnAppearShowsAddToDock() {
        let store = MockKeyValueStore()
        setResumeStep(.addToDockPromo, in: store)
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(resumeStepStore: store)
        sut.onAppear()
        XCTAssertEqual(sut.state.intro?.type, .addToDockPromoDialog)
    }

    func testWhenResumeStepIsAppIconSelectionThenOnAppearShowsAppIconPicker() {
        let store = MockKeyValueStore()
        setResumeStep(.appIconSelection, in: store)
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(resumeStepStore: store)
        sut.onAppear()
        XCTAssertEqual(sut.state.intro?.type, .chooseAppIconDialog)
    }

    func testWhenResumeStepIsAddressBarPositionSelectionThenOnAppearShowsAddressBarPicker() {
        let store = MockKeyValueStore()
        setResumeStep(.addressBarPositionSelection, in: store)
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(resumeStepStore: store)
        sut.onAppear()
        XCTAssertEqual(sut.state.intro?.type, .chooseAddressBarPositionDialog)
    }

    func testWhenResumeStepIsSearchExperienceSelectionThenOnAppearShowsSearchExperience() {
        let store = MockKeyValueStore()
        setResumeStep(.searchExperienceSelection, in: store)
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPhoneSteps(isReturningUser: false)
        let sut = makeSUT(resumeStepStore: store)
        sut.onAppear()
        XCTAssertEqual(sut.state.intro?.type, .chooseSearchExperienceDialog)
    }

    func testWhenResumeStepIsNotInCurrentFlowThenStoreIsClearedAndOnboardingStartsFromBeginning() {
        // addToDockPromo is not in the iPad flow
        let store = MockKeyValueStore()
        setResumeStep(.addToDockPromo, in: store)
        onboardingManagerMock.onboardingSteps = OnboardingStepsHelper.expectedIPadSteps(isReturningUser: false)
        _ = makeSUT(resumeStepStore: store)
        XCTAssertNil(resumeStepRawValue(in: store))
    }

}

extension OnboardingIntroViewModelTests {

    func makeSUT(
        currentOnboardingStep: OnboardingIntroStep = .introDialog(isReturningUser: false),
        onboardingSearchExperienceProvider: OnboardingSearchExperienceProvider = MockOnboardingSearchExperienceProvider(),
        restorePromptHandler: OnboardingRestorePromptHandling = MockRestorePromptHandler(),
        featureFlagger: FeatureFlagger = MockFeatureFlagger(),
        resumeStepStore: MockKeyValueStore? = nil
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
            addressBarPositionProvider: addressBarPositionProvider,
            featureFlagger: featureFlagger,
            restorePromptHandler: restorePromptHandler,
            tutorialSettings: tutorialSettingsMock,
            onboardingResumeStepStore: (resumeStepStore ?? MockKeyValueStore()).keyedStoring()
        )
    }
}

private final class MockRestorePromptHandler: OnboardingRestorePromptHandling {
    var isEligibleForRestorePromptValue = false
    private(set) var didCallRestoreSyncAccount = false

    func isEligibleForRestorePrompt() -> Bool {
        isEligibleForRestorePromptValue
    }

    func restoreSyncAccount() {
        didCallRestoreSyncAccount = true
    }
}
