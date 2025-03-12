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

final class OnboardingPixelReporterMock: OnboardingIntroPixelReporting, OnboardingSiteSuggestionsPixelReporting, OnboardingSearchSuggestionsPixelReporting, OnboardingCustomInteractionPixelReporting, OnboardingDaxDialogsReporting, OnboardingAddToDockReporting {
    private(set) var didCallMeasureOnboardingIntroImpression = false
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

    func measureOnboardingIntroImpression() {
        didCallMeasureOnboardingIntroImpression = true
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

    func measureSiteSuggetionOptionTapped() {
        didCallMeasureSiteOptionTapped = true
    }

    func measureSearchSuggetionOptionTapped() {
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
}
