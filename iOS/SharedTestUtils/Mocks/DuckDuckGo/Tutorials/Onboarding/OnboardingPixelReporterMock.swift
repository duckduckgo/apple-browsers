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

final class OnboardingPixelReporterMock: OnboardingIntroPixelReporting, OnboardingCustomInteractionPixelReporting, OnboardingDaxDialogsReporting, OnboardingAddToDockReporting {

    private(set) var didCallMeasureOnboardingIntroImpression = false
    private(set) var didCallMeasureSkipOnboardingCTAAction = false
    private(set) var didCallMeasureConfirmSkipOnboardingCTAAction = false
    private(set) var didCallMeasureResumeOnboardingCTAAction = false
    private(set) var didCallMeasureAutoRestoreOnboardingPromptShown = false
    private(set) var didCallMeasureAutoRestoreOnboardingRestoreTapped = false
    private(set) var didCallMeasureAutoRestoreOnboardingSkipTapped = false
    private(set) var didCallMeasureBrowserComparisonImpression = false
    private(set) var didCallMeasureChooseBrowserCTAAction = false
    private(set) var didCallMeasureAiComparisonImpression = false
    private(set) var didCallMeasureAiComparisonCTAAction = false
    private(set) var didCallMeasureChooseAppIconImpression = false
    private(set) var didCallMeasureChooseAppIconColor = false
    private(set) var didCaptureAppIconColorSelection: AppIcon?
    private(set) var didCallMeasureAddressBarPositionSelectionImpression = false
    private(set) var didCallMeasureChooseAddressBarPosition = false
    private(set) var didCaptureAddressBarPositionSelection: AddressBarPosition?
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
    private(set) var didCallMeasureSharedOnboardingScreenImpression = false
    private(set) var capturedSharedOnboardingScreenImpression: OnboardingSharedPixelEvent?
    private(set) var didCallMeasurePrivacyDashboardOpenedForFirstTime = false
    private(set) var didCallMeasureEndOfJourneyDialogDismiss = false

    private(set) var didCallMeasureAddToDockPromoImpression = false
    private(set) var didCallMeasureAddToDockPromoShowTutorialCTAAction = false
    private(set) var didCallMeasureAddToDockPromoDismissCTAAction = false
    private(set) var didCallMeasureAddToDockTutorialDismissCTAAction = false

    private(set) var didCallMeasureSearchExperienceSelectionImpression = false
    private(set) var didCallMeasureChooseAIChat = false
    private(set) var didCallMeasureChooseSearchOnly = false
    private(set) var didCallMeasureDuckAIQueryExperimentSelectionImpression = false
    private(set) var didCallMeasureDuckAIQueryExperimentChooseSearchOnly = false
    private(set) var didCallMeasureDuckAIQueryExperimentChooseAIChat = false
    private(set) var didCallMeasureDuckAIQueryExperimentQuerySubmission = false
    private(set) var didCaptureDuckAIQueryExperimentPromptSourceValue: String?
    private(set) var didCaptureDuckAIQueryExperimentSelection: DuckAIQueryMode?
    private(set) var didCallMeasureDuckAIExperimentFireButtonCTAAction = false
    private(set) var didCallMeasureDuckAIExperimentFireDialogImpression = false
    private(set) var didCallMeasureDuckAIExperimentFinalDialogImpression = false
    private(set) var didCallMeasureDuckAIExperimentFinalDialogCTAAction = false

    private(set) var didCallMeasureTrySearchDialogNewTabDismissButtonTapped = false
    private(set) var didCallMeasureSearchResultDialogDismissButtonTapped = false
    private(set) var didCallMeasureTryVisitSiteDialogNewTabDismissButtonTapped = false
    private(set) var didCallMeasureTryVisitSiteDismissButtonTapped = false
    private(set) var didCallMeasureTrackersDialogDismissButtonTapped = false
    private(set) var didCallMeasureFireDialogDismissButtonTapped = false
    private(set) var didCallMeasureEndOfJourneyDialogNewTabDismissButtonTapped = false
    private(set) var didCallMeasureEndOfJourneyDialogDismissButtonTapped = false
    private(set) var didCallMeasureSubscriptionPromoDialogNewTabDismissButtonTapped = false
    private(set) var didCallMeasureStartOnboardingCTAAction = false
    private(set) var didCallMeasureSkipOnboardingScreenImpression = false
    private(set) var didCallMeasureSetDefaultBrowserSkipped = false
    private(set) var didCallMeasureTrySearchDialogSuggestedSearchTapped = false
    private(set) var didCallMeasureTryVisitSiteDialogSuggestedSiteTapped = false
    private(set) var didCallMeasureSearchResultsDialogGotItAction = false
    private(set) var didCallMeasureTrackersDialogGotItAction = false
    private(set) var didCallMeasureSubscriptionPromoDialogShown = false
    private(set) var didCallMeasureSubscriptionPromoEngageCTAAction = false
    private(set) var didCallMeasureFireButtonOnboardingDeleteConfirmed = false
    private(set) var didCallMeasureFireButtonOnboardingDismissButtonTapped = false

    func measureOnboardingIntroImpression() {
        didCallMeasureOnboardingIntroImpression = true
    }

    func measureStartOnboardingCTAAction() {
        didCallMeasureStartOnboardingCTAAction = true
    }

    func measureSkipOnboardingCTAAction() {
        didCallMeasureSkipOnboardingCTAAction = true
    }

    func measureSkipOnboardingScreenImpression() {
        didCallMeasureSkipOnboardingScreenImpression = true
    }

    func measureSetDefaultBrowserSkipped() {
        didCallMeasureSetDefaultBrowserSkipped = true
    }

    func measureConfirmSkipOnboardingCTAAction() {
        didCallMeasureConfirmSkipOnboardingCTAAction = true
    }

    func measureResumeOnboardingCTAAction() {
        didCallMeasureResumeOnboardingCTAAction = true
    }

    func measureAutoRestoreOnboardingPromptShown() {
        didCallMeasureAutoRestoreOnboardingPromptShown = true
    }

    func measureAutoRestoreOnboardingRestoreCTAAction() {
        didCallMeasureAutoRestoreOnboardingRestoreTapped = true
    }

    func measureAutoRestoreOnboardingSkipCTAAction() {
        didCallMeasureAutoRestoreOnboardingSkipTapped = true
    }

    func measureBrowserComparisonImpression() {
        didCallMeasureBrowserComparisonImpression = true
    }

    func measureChooseBrowserCTAAction() {
        didCallMeasureChooseBrowserCTAAction = true
    }

    func measureAiComparisonImpression() {
        didCallMeasureAiComparisonImpression = true
    }

    func measureAiComparisonCTAAction() {
        didCallMeasureAiComparisonCTAAction = true
    }

    func measureChooseAppIconImpression() {
        didCallMeasureChooseAppIconImpression = true
    }

    func measureChooseAppIconColor(_ color: AppIcon) {
        didCallMeasureChooseAppIconColor = true
        didCaptureAppIconColorSelection = color
    }

    func measureAddressBarPositionSelectionImpression() {
        didCallMeasureAddressBarPositionSelectionImpression = true
    }

    func measureChooseAddressBarPosition(_ position: AddressBarPosition) {
        didCallMeasureChooseAddressBarPosition = true
        didCaptureAddressBarPositionSelection = position
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

    func measureScreenImpression(_ event: OnboardingSharedPixelEvent) {
        didCallMeasureSharedOnboardingScreenImpression = true
        capturedSharedOnboardingScreenImpression = event
    }

    func measureSearchResultsDialogGotItAction() {
        didCallMeasureSearchResultsDialogGotItAction = true
    }

    func measureTrackersDialogGotItAction() {
        didCallMeasureTrackersDialogGotItAction = true
    }

    func measureSubscriptionPromoDialogShown() {
        didCallMeasureSubscriptionPromoDialogShown = true
    }

    func measureSubscriptionPromoEngageCTAAction() {
        didCallMeasureSubscriptionPromoEngageCTAAction = true
    }

    func measureFireButtonOnboardingDeleteConfirmed() {
        didCallMeasureFireButtonOnboardingDeleteConfirmed = true
    }

    func measureFireButtonOnboardingDismissButtonTapped() {
        didCallMeasureFireButtonOnboardingDismissButtonTapped = true
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

    func measureSearchExperienceSelectionImpression() {
        didCallMeasureSearchExperienceSelectionImpression = true
    }

    func measureChooseAIChat() {
        didCallMeasureChooseAIChat = true
    }

    func measureChooseSearchOnly() {
        didCallMeasureChooseSearchOnly = true
    }

    func measureDuckAIQuerySelectionImpression() {
        didCallMeasureDuckAIQueryExperimentSelectionImpression = true
    }

    func measureDuckAIQueryChooseSearchOnly() {
        didCallMeasureDuckAIQueryExperimentChooseSearchOnly = true
    }

    func measureDuckAIQueryChooseAIChat() {
        didCallMeasureDuckAIQueryExperimentChooseAIChat = true
    }

    func measureDuckAIQuerySubmission(selection: DuckAIQueryMode, promptSource: DuckAIQueryPromptSource) {
        didCallMeasureDuckAIQueryExperimentQuerySubmission = true
        didCaptureDuckAIQueryExperimentPromptSourceValue = promptSource.rawValue
        didCaptureDuckAIQueryExperimentSelection = selection
    }

    func measureTrySearchDialogSuggestedSearchTapped() {
        didCallMeasureTrySearchDialogSuggestedSearchTapped = true
    }

    func measureTrySearchDialogNewTabDismissButtonTapped() {
        didCallMeasureTrySearchDialogNewTabDismissButtonTapped = true
    }

    func measureSearchResultDialogDismissButtonTapped() {
        didCallMeasureSearchResultDialogDismissButtonTapped = true
    }

    func measureTryVisitSiteDialogSuggestedSiteTapped() {
        didCallMeasureTryVisitSiteDialogSuggestedSiteTapped = true
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

    func measureDuckAIFireButtonCTAAction() {
        didCallMeasureDuckAIExperimentFireButtonCTAAction = true
    }

    func measureDuckAIFireDialogImpression() {
        didCallMeasureDuckAIExperimentFireDialogImpression = true
    }

    func measureDuckAIFinalDialogImpression() {
        didCallMeasureDuckAIExperimentFinalDialogImpression = true
    }

    func measureDuckAIFinalDialogCTAAction() {
        didCallMeasureDuckAIExperimentFinalDialogCTAAction = true
    }

    func measureEndOfJourneyDialogNewTabDismissButtonTapped() {
        didCallMeasureEndOfJourneyDialogNewTabDismissButtonTapped = true
    }

    func measureEndOfJourneyDialogDismissButtonTapped() {
        didCallMeasureEndOfJourneyDialogDismissButtonTapped = true
    }

    func measureSubscriptionDialogNewTabDismissButtonTapped() {
        didCallMeasureSubscriptionPromoDialogNewTabDismissButtonTapped = true
    }
}
