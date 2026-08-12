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

final class OnboardingPixelReporterMock: OnboardingIntroPixelReporting, OnboardingCustomInteractionPixelReporting, OnboardingDaxDialogsReporting, OnboardingAddToDockReporting, OnboardingDownloadReasonPixelReporting {

    private(set) var didCallMeasureOnboardingIntroImpression = false
    private(set) var didCallMeasureSkipOnboardingCTAAction = false
    private(set) var didCallMeasureConfirmSkipOnboardingCTAAction = false
    private(set) var didCallMeasureResumeOnboardingCTAAction = false
    private(set) var didCallMeasureAutoRestoreOnboardingPromptShown = false
    private(set) var didCallMeasureAutoRestoreOnboardingRestoreTapped = false
    private(set) var didCallMeasureAutoRestoreOnboardingSkipTapped = false
    private(set) var didCallMeasureSetDefaultBrowserImpression = false
    private(set) var didCallMeasureChooseBrowserCTAAction = false
    private(set) var didCallMeasureAiIntroImpression = false
    private(set) var didCallMeasureAiIntroCTAAction = false
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
    private(set) var didCallMeasureDuckAIQuerySelectionImpression = false
    private(set) var didCallMeasureDuckAIQueryChooseSearchOnly = false
    private(set) var didCallMeasureDuckAIQueryChooseAIChat = false
    private(set) var didCallMeasureDuckAIQueryQuerySubmission = false
    private(set) var didCaptureDuckAIQueryPromptSourceValue: String?
    private(set) var didCaptureDuckAIQuerySelection: DuckAIQueryMode?
    private(set) var didCallMeasureDuckAIFireButtonCTAAction = false
    private(set) var didCallMeasureDuckAIFireDialogImpression = false
    private(set) var didCallMeasureDuckAIFinalDialogImpression = false
    private(set) var didCallMeasureDuckAIFinalDialogCTAAction = false

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

    func measureSetDefaultBrowserImpression() {
        didCallMeasureSetDefaultBrowserImpression = true
    }

    func measureChooseBrowserCTAAction() {
        didCallMeasureChooseBrowserCTAAction = true
    }

    func measureAiIntroImpression() {
        didCallMeasureAiIntroImpression = true
    }

    func measureAiIntroCTAAction() {
        didCallMeasureAiIntroCTAAction = true
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
        didCallMeasureDuckAIQuerySelectionImpression = true
    }

    func measureDuckAIQueryChooseSearchOnly() {
        didCallMeasureDuckAIQueryChooseSearchOnly = true
    }

    func measureDuckAIQueryChooseAIChat() {
        didCallMeasureDuckAIQueryChooseAIChat = true
    }

    func measureDuckAIQuerySubmission(selection: DuckAIQueryMode, promptSource: DuckAIQueryPromptSource) {
        didCallMeasureDuckAIQueryQuerySubmission = true
        didCaptureDuckAIQueryPromptSourceValue = promptSource.rawValue
        didCaptureDuckAIQuerySelection = selection
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
        didCallMeasureDuckAIFireButtonCTAAction = true
    }

    func measureDuckAIFireDialogImpression() {
        didCallMeasureDuckAIFireDialogImpression = true
    }

    func measureDuckAIFinalDialogImpression() {
        didCallMeasureDuckAIFinalDialogImpression = true
    }

    func measureDuckAIFinalDialogCTAAction() {
        didCallMeasureDuckAIFinalDialogCTAAction = true
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

    // MARK: - Download Reason Segmented Flow

    private(set) var didCallMeasureDownloadReasonImpression = false
    private(set) var didCallMeasureDownloadReasonSelection = false
    private(set) var didCaptureDownloadReasonSelection: OnboardingDownloadReason?
    private(set) var didCallMeasureSearchPrivacySettingsImpression = false
    private(set) var didCallMeasureSearchPrivacySettingsSelection = false
    private(set) var didCaptureSearchPrivacySettingsSelection: (recentlyVisitedSitesEnabled: Bool, safeSearchEnabled: Bool)?
    private(set) var didCallMeasureAIModelImpression = false
    private(set) var didCallMeasureAIModelSelection = false
    private(set) var didCaptureAIModelSelection: String?
    private(set) var didCallMeasureToggleInputModeImpression = false
    private(set) var didCallMeasureToggleInputModeSelection = false
    private(set) var didCaptureToggleInputModeSelection: Bool?
    private(set) var didCallMeasureAISearchSettingsImpression = false
    private(set) var didCallMeasureAISearchSettingsSelection = false
    private(set) var didCaptureAISearchSettingsSelection: (searchAssistEnabled: Bool, aiGeneratedImagesEnabled: Bool)?
    private(set) var didCallMeasureKeepDuckAIImpression = false
    private(set) var didCallMeasureKeepDuckAISelection = false
    private(set) var didCaptureKeepDuckAISelection: Bool?
    private(set) var didCallMeasureDuckPlayerImpression = false
    private(set) var didCallMeasureDuckPlayerSelection = false
    private(set) var didCaptureDuckPlayerSelection: (youTubeAdBlockingEnabled: Bool, duckPlayerEnabled: Bool)?

    func measureDownloadReasonImpression() {
        didCallMeasureDownloadReasonImpression = true
    }

    func measureDownloadReasonSelection(_ reason: OnboardingDownloadReason) {
        didCallMeasureDownloadReasonSelection = true
        didCaptureDownloadReasonSelection = reason
    }

    func measureSearchPrivacySettingsImpression() {
        didCallMeasureSearchPrivacySettingsImpression = true
    }

    func measureSearchPrivacySettingsSelection(recentlyVisitedSitesEnabled: Bool, safeSearchEnabled: Bool) {
        didCallMeasureSearchPrivacySettingsSelection = true
        didCaptureSearchPrivacySettingsSelection = (recentlyVisitedSitesEnabled, safeSearchEnabled)
    }

    func measureAIModelImpression() {
        didCallMeasureAIModelImpression = true
    }

    func measureAIModelSelection(model: String) {
        didCallMeasureAIModelSelection = true
        didCaptureAIModelSelection = model
    }

    func measureToggleInputModeImpression() {
        didCallMeasureToggleInputModeImpression = true
    }

    func measureToggleInputModeSelection(openNewTabsWithAIChat: Bool) {
        didCallMeasureToggleInputModeSelection = true
        didCaptureToggleInputModeSelection = openNewTabsWithAIChat
    }

    func measureAISearchSettingsImpression() {
        didCallMeasureAISearchSettingsImpression = true
    }

    func measureAISearchSettingsSelection(searchAssistEnabled: Bool, aiGeneratedImagesEnabled: Bool) {
        didCallMeasureAISearchSettingsSelection = true
        didCaptureAISearchSettingsSelection = (searchAssistEnabled, aiGeneratedImagesEnabled)
    }

    func measureKeepDuckAIImpression() {
        didCallMeasureKeepDuckAIImpression = true
    }

    func measureKeepDuckAISelection(shouldKeep: Bool) {
        didCallMeasureKeepDuckAISelection = true
        didCaptureKeepDuckAISelection = shouldKeep
    }

    func measureDuckPlayerImpression() {
        didCallMeasureDuckPlayerImpression = true
    }

    func measureDuckPlayerSelection(youTubeAdBlockingEnabled: Bool, duckPlayerEnabled: Bool) {
        didCallMeasureDuckPlayerSelection = true
        didCaptureDuckPlayerSelection = (youTubeAdBlockingEnabled, duckPlayerEnabled)
    }
}
