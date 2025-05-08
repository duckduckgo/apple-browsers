//
//  OnboardingPixelReporterMock.swift
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

import Foundation
import Core
import Onboarding
@testable import DuckDuckGo

final class OnboardingPixelReporterMock: OnboardingIntroPixelReporting, OnboardingCustomInteractionPixelReporting, OnboardingDaxDialogsReporting, OnboardingAddToDockReporting, OnboardingSetAsDefaultBrowserExperimentReporting {
    private(set) var didCallMeasureOnboardingIntroImpression = false
    private(set) var didCallMeasureSkipOnboardingCTAAction = false
    private(set) var didCallMeasureConfirmSkipOnboardingCTAAction = false
    private(set) var didCallMeasureResumeOnboardingCTAAction = false
    private(set) var didCallMeasureBrowserComparisonImpression = false
    private(set) var didCallMeasureChooseBrowserCTAAction = false
    private(set) var didCallMeasureChooseAppIconImpression = false
    private(set) var didCallMeasureChooseCustomAppIconColor = false
    private(set) var didCallMeasureAddressBarPositionSelectionImpression = false
    private(set) var didCallMeasureChooseBottomAddressBarPosition = false
    private(set) var didCallMeasureSearchOptionTapped = false
    private(set) var didCallMeasureSiteOptionTapped = false
    private(set) var didCallMeasureCustomSearch = false
    private(set) var didCallMeasureCustomSite = false
    private(set) var didCallMeasureSecondSiteVisit = false {
        didSet {
            secondSiteVisitCounter += 1
        }
    }
    private(set) var secondSiteVisitCounter = 0
    private(set) var didCallMeasureScreenImpressionCalled = false
    private(set) var capturedScreenImpression: Pixel.Event?
    private(set) var didCallMeasurePrivacyDashboardOpenedForFirstTime = false
    private(set) var didCallMeasureEndOfJourneyDialogDismiss = false

    private(set) var didCallMeasureAddToDockPromoImpression = false
    private(set) var didCallMeasureAddToDockPromoShowTutorialCTAAction = false
    private(set) var didCallMeasureAddToDockPromoDismissCTAAction = false
    private(set) var didCallMeasureAddToDockTutorialDismissCTAAction = false

    private(set) var didCallMeasureDidSetDDGAsDefaultBrowser = false
    private(set) var didCallMeasureDidNotSetDDGAsDefaultBrowser = false

    private(set) var didCallMeasureTrySearchDialogNewTabDismissButtonTapped = false
    private(set) var didCallMeasureSearchResultDialogDismissButtonTapped = false
    private(set) var didCallMeasureTryVisitSiteDialogNewTabDismissButtonTapped = false
    private(set) var didCallMeasureTryVisitSiteDismissButtonTapped = false
    private(set) var didCallMeasureTrackersDialogDismissButtonTapped = false
    private(set) var didCallMeasureFireDialogDismissButtonTapped = false
    private(set) var didCallMeasureEndOfJourneyDialogNewTabDismissButtonTapped = false
    private(set) var didCallMeasureEndOfJourneyDialogDismissButtonTapped = false
    private(set) var didCallMeasurePrivacyProPromoDialogNewTabDismissButtonTapped = false

    func measureOnboardingIntroImpression() {
        didCallMeasureOnboardingIntroImpression = true
    }

    func measureSkipOnboardingCTAAction() {
        didCallMeasureSkipOnboardingCTAAction = true
    }

    func measureConfirmSkipOnboardingCTAAction() {
        didCallMeasureConfirmSkipOnboardingCTAAction = true
    }

    func measureResumeOnboardingCTAAction() {
        didCallMeasureResumeOnboardingCTAAction = true
    }

    func measureBrowserComparisonImpression() {
        didCallMeasureBrowserComparisonImpression = true
    }

    func measureChooseBrowserCTAAction() {
        didCallMeasureChooseBrowserCTAAction = true
    }

    func measureChooseAppIconImpression() {
        didCallMeasureChooseAppIconImpression = true
    }

    func measureChooseCustomAppIconColor() {
        didCallMeasureChooseCustomAppIconColor = true
    }

    func measureAddressBarPositionSelectionImpression() {
        didCallMeasureAddressBarPositionSelectionImpression = true
    }

    func measureChooseBottomAddressBarPosition() {
        didCallMeasureChooseBottomAddressBarPosition = true
    }

    func measureEndOfJourneyDialogCTAAction() {
        didCallMeasureEndOfJourneyDialogDismiss = true
    }

    func measureSiteSuggestionOptionTapped() {
        didCallMeasureSiteOptionTapped = true
    }

    func measureSearchSuggestionOptionTapped() {
        didCallMeasureSearchOptionTapped = true
    }

    func measureCustomSearch() {
        didCallMeasureCustomSearch = true
    }

    func measureCustomSite() {
        didCallMeasureCustomSite = true
    }

    func measureSecondSiteVisit() {
        didCallMeasureSecondSiteVisit = true
    }

    func measureScreenImpression(event: Pixel.Event) {
        didCallMeasureScreenImpressionCalled = true
        capturedScreenImpression = event
    }

    func measurePrivacyDashboardOpenedForFirstTime() {
        didCallMeasurePrivacyDashboardOpenedForFirstTime = true
    }

    func measureAddToDockPromoImpression() {
        didCallMeasureAddToDockPromoImpression = true
    }

    func measureAddToDockPromoShowTutorialCTAAction() {
        didCallMeasureAddToDockPromoShowTutorialCTAAction = true
    }

    func measureAddToDockPromoDismissCTAAction() {
        didCallMeasureAddToDockPromoDismissCTAAction = true
    }

    func measureAddToDockTutorialDismissCTAAction() {
        didCallMeasureAddToDockTutorialDismissCTAAction = true
    }

    func measureDidSetDDGAsDefaultBrowser() {
        didCallMeasureDidSetDDGAsDefaultBrowser = true
    }

    func measureDidNotSetDDGAsDefaultBrowser() {
        didCallMeasureDidNotSetDDGAsDefaultBrowser = true
    }

    func measureTrySearchDialogNewTabDismissButtonTapped() {
        didCallMeasureTrySearchDialogNewTabDismissButtonTapped = true
    }

    func measureSearchResultDialogDismissButtonTapped() {
        didCallMeasureSearchResultDialogDismissButtonTapped = true
    }

    func measureTryVisitSiteDialogNewTabDismissButtonTapped() {
        didCallMeasureTryVisitSiteDialogNewTabDismissButtonTapped = true
    }

    func measureTryVisitSiteDialogDismissButtonTapped() {
        didCallMeasureTryVisitSiteDismissButtonTapped = true
    }

    func measureTrackersDialogDismissButtonTapped() {
        didCallMeasureTrackersDialogDismissButtonTapped = true
    }

    func measureFireDialogDismissButtonTapped() {
        didCallMeasureFireDialogDismissButtonTapped = true
    }

    func measureEndOfJourneyDialogNewTabDismissButtonTapped() {
        didCallMeasureEndOfJourneyDialogNewTabDismissButtonTapped = true
    }

    func measureEndOfJourneyDialogDismissButtonTapped() {
        didCallMeasureEndOfJourneyDialogDismissButtonTapped = true
    }

    func measurePrivacyPromoDialogNewTabDismissButtonTapped() {
        didCallMeasurePrivacyProPromoDialogNewTabDismissButtonTapped = true
    }
}
