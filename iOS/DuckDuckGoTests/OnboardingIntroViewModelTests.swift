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
@testable import DuckDuckGo

@MainActor
final class OnboardingIntroViewModelTests: XCTestCase {
    private var defaultBrowserManagerMock: DefaultBrowserManagerMock!
    private var contextualDaxDialogs: ContextualOnboardingLogicMock!
    private var pixelReporterMock: OnboardingPixelReporterMock!
    private var onboardingManagerMock: OnboardingManagerMock!
    private var urlOpenerMock: MockURLOpener!
    private var appIconProvider: (() -> AppIcon)!
    private var addressBarPositionProvider: (() -> AddressBarPosition)!

    override func setUp() {
        super.setUp()
        defaultBrowserManagerMock = DefaultBrowserManagerMock()
        contextualDaxDialogs = ContextualOnboardingLogicMock()
        pixelReporterMock = OnboardingPixelReporterMock()
        onboardingManagerMock = OnboardingManagerMock()
        urlOpenerMock = MockURLOpener()
        appIconProvider = { .defaultAppIcon }
        addressBarPositionProvider = { .top }
    }

    override func tearDown() {
        defaultBrowserManagerMock = nil
        contextualDaxDialogs = nil
        pixelReporterMock = nil
        onboardingManagerMock = nil
        urlOpenerMock = nil
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

    func testWhenSetDefaultBrowserActionIsCalledThenURLOpenerOpensURL() {
        // GIVEN
        let urlPath = UIApplication.openSettingsURLString
        onboardingManagerMock.settingsURLPath = urlPath
        let sut = makeSUT()
        XCTAssertFalse(urlOpenerMock.didCallOpenURL)
        XCTAssertNil(urlOpenerMock.capturedURL)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(onboardingManagerMock.didCallSettingsURLPath)
        XCTAssertTrue(urlOpenerMock.didCallOpenURL)
        XCTAssertEqual(urlOpenerMock.capturedURL?.absoluteString, urlPath)
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

    func testWhenOnAppearIsCalledThenPixelReporterTrackOnboardingIntroImpression() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureOnboardingIntroImpression)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureOnboardingIntroImpression)
    }

    func testWhenStartOnboardingActionIsCalledThenPixelReporterTrackBrowserComparisonImpression() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureBrowserComparisonImpression)

        // WHEN
        sut.startOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureBrowserComparisonImpression)
    }

    func testWhenAppIconScreenPresentedThenPixelReporterTrackAppIconImpression() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: false)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)
        XCTAssertFalse(pixelReporterMock.didCallMeasureBrowserComparisonImpression)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseAppIconImpression)
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIconIsCustomColorThenPixelReporterTrackCustomAppIconColor() {
        // GIVEN
        appIconProvider = { .purple }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIconIsDefaultColorThenPixelReporterDoNotTrackCustomAppIconColor() {
        // GIVEN
        appIconProvider = { .defaultAppIcon }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseCustomAppIconColor)
    }

    func testWhenStateChangesToChooseAddressBarPositionThenPixelReporterTrackAddressBarSelectionImpression() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .appIconSelection)
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddressBarPositionSelectionImpression)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddressBarPositionSelectionImpression)
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndAddressBarPositionIsBottomThenPixelReporterTrackChooseBottomAddressBarPosition() {
        // GIVEN
        addressBarPositionProvider = { .bottom }
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseBottomAddressBarPosition)

        // WHEN
        sut.selectAddressBarPositionAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseBottomAddressBarPosition)
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndAddressBarPositionIsTopThenPixelReporterDoNotTrackChooseBottomAddressBarPosition() {
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

    func testWhenSkipOnboardingActionIsCalledThenPixelReporterTrackSkipOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(pixelReporterMock.didCallMeasureSkipOnboardingCTAAction)

        // WHEN
        sut.skipOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureSkipOnboardingCTAAction)
    }

    func testWhenConfirmSkipOnboardingActionIsCalledThenPixelReporterTrackConfirmSkipOnboardingCTA() {
        // GIVEN
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.returningUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .introDialog(isReturningUser: true))
        XCTAssertFalse(pixelReporterMock.didCallMeasureConfirmSkipOnboardingCTAAction)

        // WHEN
        sut.confirmSkipOnboardingAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureConfirmSkipOnboardingCTAAction)
    }

    func testWhenStartOnboardingActionResumingTrueIsCalledThenPixelReporterTrackResumeOnboardingCTA() {
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

    func testWhenStateChangesToAddToDockPromoThenPixelReporterTrackAddToDockPromoImpression() {
        // GIVEN
        let sut = makeSUT(currentOnboardingStep: .browserComparison)
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockPromoImpression)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockPromoImpression)
    }

    func testWhenAddToDockShowTutorialActionIsCalledThenPixelReporterTrackAddToDockPromoShowTutorialCTA() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockPromoShowTutorialCTAAction)

        // WHEN
        sut.addToDockShowTutorialAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockPromoShowTutorialCTAAction)
    }

    func testWhenAddToDockContinueActionIsCalledAndIsShowingFromAddToDockTutorialIsTrueThenPixelReporterTrackAddToDockTutorialDismissCTA() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockTutorialDismissCTAAction)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: true)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockTutorialDismissCTAAction)
    }

    func testWhenAddToDockContinueActionIsCalledAndIsShowingFromAddToDockTutorialIsFalseThenPixelReporterTrackAddToDockTutorialDismissCTA() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureAddToDockPromoDismissCTAAction)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: false)

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureAddToDockPromoDismissCTAAction)
    }

    // MARK: - Set As Default Experiment

    func testWhenAppIconPickerContinueActionIsCalledAndSetAsDefaultBrowserEnabledThenCheckIfBrowserIsDefault() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserPipVideoExperiment = true
        let sut = makeSUT()
        XCTAssertFalse(defaultBrowserManagerMock.didCallDefaultBrowserInfo)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(defaultBrowserManagerMock.didCallDefaultBrowserInfo)
    }

    func testWhenAppIconPickerContinueActionIsCalledAndSetAsDefaultBrowserDisabledThenDoNotCheckIfBrowserIsDefault() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserPipVideoExperiment = false
        let sut = makeSUT()
        XCTAssertFalse(defaultBrowserManagerMock.didCallDefaultBrowserInfo)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(defaultBrowserManagerMock.didCallDefaultBrowserInfo)
    }

    func testWhenDefaultBrowserInfoIsSuccessfulResult_AndIsDefaultBrowserIsTrue_ThenFireDidSetDefaultBrowserPixel() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserPipVideoExperiment = true
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: true)
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)
    }

    func testWhenDefaultBrowserInfoIsSuccessfulResult_AndIsDefaultBrowserIsFalse_ThenFireDidNotSetDefaultBrowserPixel() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserPipVideoExperiment = true
        defaultBrowserManagerMock.resultToReturn = .successful(isDefaultBrowser: false)
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertTrue(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)
    }

    func testWhenDefaultBrowserInfoIsFailureResult_AndFailureIsRateLimited_ThenDoNotFireSetDefaultBrowserPixels() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserPipVideoExperiment = true
        defaultBrowserManagerMock.resultToReturn = .failed(reason: .rateLimitReached(updatedStoredInfo: nil))
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)
    }

    func testWhenDefaultBrowserInfoIsFailureResult_AndFailureIsUnkownError_ThenDoNotFireSetDefaultBrowserPixels() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserPipVideoExperiment = true
        defaultBrowserManagerMock.resultToReturn = .failed(reason: .unknownError(NSError(domain: #function, code: 0)))
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)
    }

    func testWhenDefaultBrowserInfoIsFailureResult_AndFailureIsNotSupportedOnCurrentOSVersion_ThenDoNotFireSetDefaultBrowserPixels() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserPipVideoExperiment = true
        defaultBrowserManagerMock.resultToReturn = .failed(reason: .notSupportedOnCurrentOSVersion)
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidSetDDGAsDefaultBrowser)
        XCTAssertFalse(pixelReporterMock.didCallMeasureDidNotSetDDGAsDefaultBrowser)
    }

    // MARK: - Set As Default Browser PiP Experiment

    func testWhenEnrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial_AndUserIsNotEnrolledInExperiment_ThenDoNotShowVideoTutorial() {
        // GIVEN
        onboardingManagerMock.cohortToReturn = nil
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT()

        // WHEN
        let result = sut.enrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial()

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenEnrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial_AndUserIsInControlGroup_ThenDoNotShowVideoTutorial() {
        // GIVEN
        onboardingManagerMock.cohortToReturn = .control
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT()

        // WHEN
        let result = sut.enrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial()

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenEnrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial_AndUserIsInTreatmentGroup_ThenShowVideoTutorial() {
        // GIVEN
        onboardingManagerMock.cohortToReturn = .treatment
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT()

        // WHEN
        let result = sut.enrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial()

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenEnrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial_ThenPixelReporterTrackChooseBrowserCTAAction() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseBrowserCTAAction)

        // WHEN
        _ = sut.enrollUserInPiPVideoExperimentAndCheckIfShouldShowVideoTutorial()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseBrowserCTAAction)
    }

    func testWhenSetDefaultBrowserActionIsCalled_AndUserIsInControlGroup_ThenMakeNextViewState() {
        // GIVEN
        onboardingManagerMock.cohortToReturn = .control
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenSetDefaultBrowserActionIsCalled_AndUserNotEnrolledInPiPExperiment_ThenMakeNextViewState() {
        // GIVEN
        onboardingManagerMock.cohortToReturn = nil
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenSetDefaultBrowserActionIsCalled_AndUserIsInTreatmentGroup_ThenDoNotMakeNextViewState() {
        // GIVEN
        onboardingManagerMock.cohortToReturn = .treatment
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertNotEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenCompletedSetDefaultBrowserActionIsCalled_ThenMakeNextViewState() {
        onboardingManagerMock.onboardingSteps = OnboardingIntroStep.newUserSteps(isIphone: true)
        let sut = makeSUT(currentOnboardingStep: .browserComparison)

        // WHEN
        sut.completedSetDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

}

extension OnboardingIntroViewModelTests {

    func makeSUT(currentOnboardingStep: OnboardingIntroStep = .introDialog(isReturningUser: false)) -> OnboardingIntroViewModel {
        OnboardingIntroViewModel(
            defaultBrowserManager: defaultBrowserManagerMock,
            contextualDaxDialogs: contextualDaxDialogs,
            pixelReporter: pixelReporterMock,
            onboardingManager: onboardingManagerMock,
            urlOpener: urlOpenerMock,
            currentOnboardingStep: currentOnboardingStep,
            appIconProvider: appIconProvider,
            addressBarPositionProvider: addressBarPositionProvider
        )
    }
    
}
