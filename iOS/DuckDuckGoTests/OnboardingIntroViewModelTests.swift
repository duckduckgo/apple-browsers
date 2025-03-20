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
    private var pixelReporterMock: OnboardingPixelReporterMock!
    private var onboardingManagerMock: OnboardingManagerMock!
    private var isIpad: Bool!
    private var urlOpenerMock: MockURLOpener!
    private var appIconProvider: (() -> AppIcon)!
    private var addressBarPositionProvider: (() -> AddressBarPosition)!

    override func setUp() {
        super.setUp()
        defaultBrowserManagerMock = DefaultBrowserManagerMock()
        pixelReporterMock = OnboardingPixelReporterMock()
        onboardingManagerMock = OnboardingManagerMock()
        isIpad = false
        urlOpenerMock = MockURLOpener()
        appIconProvider = { .defaultAppIcon }
        addressBarPositionProvider = { .top }
    }

    override func tearDown() {
        defaultBrowserManagerMock = nil
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
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog, step: .hidden)))
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
        isIpad = false
        let sut = makeSUT()

        // WHEN
        let result = sut.state

        // THEN
        XCTAssertEqual(result, .landing)
    }

    func testWhenOnAppearIsCalledAndAndIsIphoneFlowThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() {
        // GIVEN
        isIpad = false
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog, step: .hidden)))
    }


    func testWhenSetDefaultBrowserActionIsCalledAndIsIphoneFlowThenViewStateChangesToAddToDockPromoDialogAndProgressIs2Of4() {
        // GIVEN
        isIpad = false
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenCancelSetDefaultBrowserActionIsCalledAndIsIphoneFlowThenViewStateChangesToAddToDockPromoDialogAndProgressIs2Of4() {
        // GIVEN
        isIpad = false
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.cancelSetDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .addToDockPromoDialog, step: .init(currentStep: 2, totalSteps: 4))))
    }

    func testWhenAddtoDockContinueActionIsCalledAndIsIphoneFlowThenThenViewStateChangesToChooseAppIconAndProgressIs3of4() {
        // GIVEN
        isIpad = false
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.addToDockContinueAction(isShowingAddToDockTutorial: false)

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 3, totalSteps: 4))))
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIsIphoneFlowThenViewStateChangesToChooseAddressBarPositionDialogAndProgressIs4Of4() {
        // GIVEN
        isIpad = false
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAddressBarPositionDialog, step: .init(currentStep: 4, totalSteps: 4))))
    }

    func testWhenSelectAddressBarPositionActionIsCalledAndIsIphoneFlowThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        isIpad = false
        let sut = makeSUT()
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
        isIpad = true
        let sut = makeSUT()

        // WHEN
        let result = sut.state

        // THEN
        XCTAssertEqual(result, .landing)
    }

    func testWhenOnAppearIsCalledAndAndIsIpadFlowThenViewStateChangesToStartOnboardingDialogAndProgressIsHidden() {
        // GIVEN
        isIpad = true
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.onAppear()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .startOnboardingDialog, step: .hidden)))
    }

    func testWhenStartOnboardingActionIsCalledAndIsIpadFlowThenViewStateChangesToBrowsersComparisonDialogAndProgressIs1Of3() {
        // GIVEN
        isIpad = true
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.startOnboardingAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .browsersComparisonDialog, step: .init(currentStep: 1, totalSteps: 2))))
    }

    func testWhenSetDefaultBrowserActionIsCalledAndIsIpadFlowThenViewStateChangesToChooseAppIconDialogAndProgressIs2Of3() {
        // GIVEN
        isIpad = true
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 2, totalSteps: 2))))
    }

    func testWhenCancelSetDefaultBrowserActionIsCalledAndIsIpadFlowThenViewStateChangesToChooseAppIconDialogAndProgressIs2Of3() {
        // GIVEN
        isIpad = true
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .landing)

        // WHEN
        sut.cancelSetDefaultBrowserAction()

        // THEN
        XCTAssertEqual(sut.state, .onboarding(.init(type: .chooseAppIconDialog, step: .init(currentStep: 2, totalSteps: 2))))
    }

    func testWhenAppIconPickerContinueActionIsCalledAndIsIphoneFlowThenOnCompletingOnboardingIntroIsCalled() {
        // GIVEN
        var didCallOnCompletingOnboardingIntro = false
        isIpad = true
        let sut = makeSUT()
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

    func testWhenChooseBrowserIsCalledThenPixelReporterTrackChooseBrowserCTAAction() {
        // GIVEN
        let sut = makeSUT()
        XCTAssertFalse(pixelReporterMock.didCallMeasureChooseBrowserCTAAction)

        // WHEN
        sut.setDefaultBrowserAction()

        // THEN
        XCTAssertTrue(pixelReporterMock.didCallMeasureChooseBrowserCTAAction)
    }

    func testWhenAppIconScreenPresentedThenPixelReporterTrackAppIconImpression() {
        // GIVEN
        isIpad = true
        let sut = makeSUT()
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
        isIpad = false
        let sut = makeSUT()
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
        let sut = makeSUT()
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
        sut.addtoDockShowTutorialAction()

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
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserExperiment = true
        let sut = makeSUT()
        XCTAssertFalse(defaultBrowserManagerMock.didCallDefaultBrowserInfo)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertTrue(defaultBrowserManagerMock.didCallDefaultBrowserInfo)
    }

    func testWhenAppIconPickerContinueActionIsCalledAndSetAsDefaultBrowserDisabledThenDoNotCheckIfBrowserIsDefault() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserExperiment = false
        let sut = makeSUT()
        XCTAssertFalse(defaultBrowserManagerMock.didCallDefaultBrowserInfo)

        // WHEN
        sut.appIconPickerContinueAction()

        // THEN
        XCTAssertFalse(defaultBrowserManagerMock.didCallDefaultBrowserInfo)
    }

    func testWhenDefaultBrowserInfoIsSuccessfulResult_AndIsDefaultBrowserIsTrue_ThenFireDidSetDefaultBrowserPixel() {
        // GIVEN
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserExperiment = true
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
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserExperiment = true
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
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserExperiment = true
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
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserExperiment = true
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
        onboardingManagerMock.isEnrolledInSetAsDefaultBrowserExperiment = true
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

}

extension OnboardingIntroViewModelTests {

    func makeSUT() -> OnboardingIntroViewModel {
        OnboardingIntroViewModel(
            defaultBrowserManager: defaultBrowserManagerMock,
            pixelReporter: pixelReporterMock,
            onboardingManager: onboardingManagerMock,
            isIpad: isIpad,
            urlOpener: urlOpenerMock,
            appIconProvider: appIconProvider,
            addressBarPositionProvider: addressBarPositionProvider
        )
    }
    
}
