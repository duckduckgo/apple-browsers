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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT()

        // WHEN
        let result = sut.state

        // THEN
        XCTAssertEqual(result, .landing)
    }

    func testWhenOnAppearIsCalled_AndIsNewUser_AndAndIsIphoneFlow_ThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)

        // WHEN
        sut.startOnboardingAction(isResumingOnboarding: true)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 4))))
    }

    func testWhenConfirmSkipOnboarding_andIsIphoneFlow_ThenDismissOnboardingAndDisableDaxDialogs() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenCancelSetDefaultBrowserActionIsCalledAndIsIphoneFlowThenViewStateChangesToAddToDockPromoDialogAndProgressIs2Of4() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.cancelSetDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenAddtoDockContinueActionIsCalledAndIsIphoneFlowThenThenViewStateChangesToChooseAppIconAndProgressIs3of4() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .addToDockPromo)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: false)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 3, totalSteps: 4))))
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIsIphoneFlowThenViewStateChangesToChooseAddressBarPositionDialogAndProgressIs4Of4() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAddressBarPositionDialog, step: .init(currentStep: 4, totalSteps: 4))))
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndIsIphoneFlowThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
        let sut = makeSUT()

        // WHEN
        let result = sut.state

        // THEN
        XCTAssertEqual(result, .landing)
    }

    func testWhenOnAppearIsCalled_AndIsNewUser_AndAndIsIpadFlow_ThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: false)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: false)
        let currentStep = try XCTUnwrap(onboardingManagerMock.onboardingSteps.first)
        let sut = makeSUT(currentOnboardingStep: currentStep)

        // WHEN
        sut.startOnboardingAction(isResumingOnboarding: true)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 2))))
    }

    func testWhenConfirmSkipOnboarding_andIsIpadFlow_ThenDismissOnboardingAndDisableDaxDialogs() throws {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: false)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.startOnboardingAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 2))))
    }

    func testWhenSetDefaultBrowserActionIsCalledAndIsIpadFlowThenViewStateChangesToChooseAppIconDialogAndProgressIs2Of3() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 2, totalSteps: 2))))
    }

    func testWhenCancelSetDefaultBrowserActionIsCalledAndIsIpadFlowThenViewStateChangesToChooseAppIconDialogAndProgressIs2Of3() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.cancelSetDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 2, totalSteps: 2))))
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIsIphoneFlowThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
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
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(pixelReporterMock.didCallMeasureSkipOnboardingCTAAction)

        // WHEN
        sut.skipOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureSkipOnboardingCTAAction)
    }

    func testWhenConfirmSkipOnboardingActionIsCalledThenPixelReporterMeasureConfirmSkipOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(pixelReporterMock.didCallMeasureConfirmSkipOnboardingCTAAction)

        // WHEN
        sut.confirmSkipOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureConfirmSkipOnboardingCTAAction)
    }

    func testWhenStartOnboardingActionResumingTrueIsCalledThenPixelReporterMeasureResumeOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
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

}

extension OnboardingIntroViewModelTests {

    func makeSUT(currentOnboardingStep: OnboardingIntroStep = .introDialog(isReturningUser: false)) -> OnboardingIntroViewModel {
        OnboardingIntroViewModel(
            defaultBrowserManager: defaultBrowserManagerMock,
            contextualDaxDialogs: contextualDaxDialogs,
            pixelReporter: pixelReporterMock,
            onboardingManager: onboardingManagerMock,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
            currentOnboardingStep: currentOnboardingStep,
            appIconProvider: appIconProvider,
            addressBarPositionProvider: addressBarPositionProvider
        )
    }
    
}
