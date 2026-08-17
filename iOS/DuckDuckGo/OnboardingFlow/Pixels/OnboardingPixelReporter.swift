//
//  OnboardingPixelReporter.swift
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
import BrowserServicesKit
import Core
import PrivacyConfig
import Onboarding
import Persistence
import PixelKit
import PixelExperimentKit
import FeatureFlags_iOS

// MARK: - Pixel Fire Interface

protocol OnboardingPixelFiring {
    static func fire(pixel: Pixel.Event, withAdditionalParameters params: [String: String], includedParameters: [Pixel.QueryParameters])
}

extension Pixel: OnboardingPixelFiring {
    static func fire(pixel: Event, withAdditionalParameters params: [String: String], includedParameters: [QueryParameters]) {
        self.fire(pixel: pixel, withAdditionalParameters: params, includedParameters: includedParameters, onComplete: { _ in })
    }
}

extension UniquePixel: OnboardingPixelFiring {
    static func fire(pixel: Pixel.Event, withAdditionalParameters params: [String: String], includedParameters: [Pixel.QueryParameters]) {
        self.fire(pixel: pixel, withAdditionalParameters: params, includedParameters: includedParameters, onComplete: { _ in })
    }
}

// MARK: - OnboardingPixelReporter

protocol OnboardingIntroImpressionReporting {
    func measureOnboardingIntroImpression()
}

protocol OnboardingIntroPixelReporting: OnboardingIntroImpressionReporting {
    func measureStartOnboardingCTAAction()
    func measureSkipOnboardingCTAAction()
    func measureConfirmSkipOnboardingCTAAction()
    func measureResumeOnboardingCTAAction()
    func measureAutoRestoreOnboardingPromptShown()
    func measureAutoRestoreOnboardingRestoreCTAAction()
    func measureAutoRestoreOnboardingSkipCTAAction()
    func measureSetDefaultBrowserImpression()
    func measureChooseBrowserCTAAction()
    func measureAiIntroImpression()
    func measureAiIntroCTAAction()
    func measureChooseAppIconImpression()
    func measureChooseAppIconColor(_ color: AppIcon)
    func measureAddressBarPositionSelectionImpression()
    func measureChooseAddressBarPosition(_ position: AddressBarPosition)
    func measureSearchExperienceSelectionImpression()
    func measureChooseAIChat()
    func measureChooseSearchOnly()
    func measureDuckAIQuerySelectionImpression()
    func measureDuckAIQueryChooseSearchOnly()
    func measureDuckAIQueryChooseAIChat()
    func measureDuckAIQuerySubmission(selection: DuckAIQueryMode, promptSource: DuckAIQueryPromptSource)
    func measureSkipOnboardingScreenImpression()
    func measureSetDefaultBrowserSkipped()
}


protocol OnboardingCustomInteractionPixelReporting {
    func measureCustomSearch()
    func measureCustomSite()
    func measureSecondSiteVisit()
    func measurePrivacyDashboardOpenedForFirstTime()
}

protocol OnboardingDaxDialogsReporting {
    func measureScreenImpression(event: Pixel.Event)
    func measureScreenImpression(_ event: OnboardingSharedPixelEvent)
    func measureSearchResultsDialogGotItAction()
    func measureTrackersDialogGotItAction()
    func measureSubscriptionPromoDialogShown()
    func measureSubscriptionPromoEngageCTAAction()
    func measureFireButtonOnboardingDeleteConfirmed()
    func measureFireButtonOnboardingDismissButtonTapped()
    func measureTrySearchDialogSuggestedSearchTapped()
    func measureTrySearchDialogNewTabDismissButtonTapped()
    func measureSearchResultDialogDismissButtonTapped()
    func measureTryVisitSiteDialogSuggestedSiteTapped()
    func measureTryVisitSiteDialogNewTabDismissButtonTapped()
    func measureTryVisitSiteDialogDismissButtonTapped()
    func measureTrackersDialogDismissButtonTapped()
    func measureFireDialogDismissButtonTapped()
    func measureDuckAIFireButtonCTAAction()
    func measureDuckAIFireDialogImpression()
    func measureDuckAIFinalDialogImpression()
    func measureDuckAIFinalDialogCTAAction()
    func measureEndOfJourneyDialogNewTabDismissButtonTapped()
    func measureEndOfJourneyDialogDismissButtonTapped()
    func measureSubscriptionDialogNewTabDismissButtonTapped()
    func measureEndOfJourneyDialogCTAAction()
    func measureEndOfJourneyTryDuckAICTAAction()
    func measureEndOfJourneyTryDuckAISkipAction()
}


protocol OnboardingAddToDockReporting {
    func measureAddToDockPromoImpression()
    func measureAddToDockPromoShowTutorialCTAAction()
    func measureAddToDockPromoDismissCTAAction()
    func measureAddToDockTutorialDismissCTAAction()
}

/// Reporting for the download-reason segmented onboarding flow (treatment cohort only): the download-reason
/// screen and the tailored preferences steps that follow it.
protocol OnboardingDownloadReasonPixelReporting {
    func measureDownloadReasonImpression()
    func measureDownloadReasonSelection(_ reason: OnboardingDownloadReason)
    func measureSearchPrivacySettingsImpression()
    func measureSearchPrivacySettingsSelection(recentlyVisitedSitesEnabled: Bool, safeSearchEnabled: Bool)
    func measureAIModelImpression()
    func measureAIModelSelection(model: String)
    func measureToggleInputModeImpression()
    func measureToggleInputModeSelection(openNewTabsWithAIChat: Bool)
    func measureAISearchSettingsImpression()
    func measureAISearchSettingsSelection(searchAssistEnabled: Bool, aiGeneratedImagesEnabled: Bool)
    func measureKeepDuckAIImpression()
    func measureKeepDuckAISelection(shouldKeep: Bool)
    func measureDuckPlayerImpression()
    func measureDuckPlayerSelection(youTubeAdBlockingEnabled: Bool, duckPlayerEnabled: Bool)
}

typealias LinearOnboardingPixelReporting = OnboardingIntroPixelReporting & OnboardingAddToDockReporting & OnboardingDownloadReasonPixelReporting
typealias OnboardingPixelReporting = LinearOnboardingPixelReporting & OnboardingCustomInteractionPixelReporting & OnboardingDaxDialogsReporting

// MARK: - Implementation

final class OnboardingPixelReporter {
    private let pixel: OnboardingPixelFiring.Type
    private let uniquePixel: OnboardingPixelFiring.Type
    private let statisticsStore: StatisticsStore
    private let calendar: Calendar
    private let dateProvider: () -> Date
    private let userDefaults: UserDefaults
    private let sharedPixelHandler: OnboardingSharedPixelHandling
    private let sharedPixelsStorage: any KeyedStoring<OnboardingSharedPixelsKeys>
    private let siteVisitedUserDefaultsKey = "com.duckduckgo.ios.site-visited"
    private let downloadReasonExperimentMetric: OnboardingDownloadReasonExperimentMetric

    init(
        pixel: OnboardingPixelFiring.Type = Pixel.self,
        uniquePixel: OnboardingPixelFiring.Type = UniquePixel.self,
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        calendar: Calendar = .current,
        dateProvider: @escaping () -> Date = Date.init,
        userDefaults: UserDefaults = UserDefaults.app,
        sharedPixelHandler: OnboardingSharedPixelHandling? = nil,
        sharedPixelsStorage: (any KeyedStoring<OnboardingSharedPixelsKeys>)? = nil,
        downloadReasonExperimentMetric: OnboardingDownloadReasonExperimentMetric = OnboardingDownloadReasonExperimentMetric()
    ) {
        self.pixel = pixel
        self.uniquePixel = uniquePixel
        self.statisticsStore = statisticsStore
        self.calendar = calendar
        self.dateProvider = dateProvider
        self.userDefaults = userDefaults
        self.sharedPixelHandler = sharedPixelHandler ?? OnboardingSharedPixelHandler(
            platform: .iOS,
            installTypeProvider: { OnboardingManager().isNewUser ? .newInstall : .reinstall },
            installDateProvider: { statisticsStore.installDate }
        )
        self.sharedPixelsStorage = if let sharedPixelsStorage { sharedPixelsStorage } else { UserDefaults.app.keyedStoring() }
        self.downloadReasonExperimentMetric = downloadReasonExperimentMetric
    }

    private func fire(event: Pixel.Event, unique: Bool, additionalParameters: [String: String] = [:], includedParameters: [Pixel.QueryParameters] = [.appVersion]) {
        if unique {
            uniquePixel.fire(pixel: event, withAdditionalParameters: additionalParameters, includedParameters: includedParameters)
        } else {
            pixel.fire(pixel: event, withAdditionalParameters: additionalParameters, includedParameters: includedParameters)
        }
    }

    // Fires a shared onboarding pixel with the current stored context (source, flow and variant).
    private func fireSharedPixel(_ event: OnboardingSharedPixelEvent) {
        sharedPixelHandler.fire(event,
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    // Records the onboarding variant only if one hasn't been set yet, so the first branching
    // choice wins and a later step can't overwrite it.
    private func setVariantIfNotAlreadySet(_ variant: OnboardingPixelParameter.Variant) {
        guard sharedPixelsStorage.onboardingVariant == nil else { return }
        sharedPixelsStorage.onboardingVariant = variant
    }

}

enum DuckAIQueryPromptSource: String {
    case custom
    case option1
    case option2
    case option3
}

extension AppIcon {
    var pixelValue: OnboardingSharedPixelEvent.AppIconColorEvent.Value {
        switch self {
        case .red: .red
        case .pink: .pink
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .black: .black
        case .white: .white
        }
    }
}

// MARK: - OnboardingPixelReporter + Intro

extension OnboardingPixelReporter: OnboardingIntroPixelReporting {

    func measureStartOnboardingCTAAction() {
        fireSharedPixel(.welcome(.clicked(.engage)))
    }

    func measureSkipOnboardingCTAAction() {
        fire(event: .onboardingIntroSkipOnboardingCTAPressed, unique: false)
        fireSharedPixel(.welcome(.clicked(.dismiss)))
    }

    func measureConfirmSkipOnboardingCTAAction() {
        fire(event: .onboardingIntroConfirmSkipOnboardingCTAPressed, unique: false)
        fireSharedPixel(.skipOnboarding(.clicked(.engage)))
    }

    func measureResumeOnboardingCTAAction() {
        fire(event: .onboardingIntroResumeOnboardingCTAPressed, unique: false)
        fireSharedPixel(.skipOnboarding(.clicked(.dismiss)))
    }

    func measureAutoRestoreOnboardingPromptShown() {
        fire(event: .syncAutoRestoreOnboardingPromptShownUnique, unique: true)
    }

    func measureAutoRestoreOnboardingRestoreCTAAction() {
        fire(event: .syncAutoRestoreOnboardingRestoreTappedUnique, unique: true)
    }

    func measureAutoRestoreOnboardingSkipCTAAction() {
        fire(event: .syncAutoRestoreOnboardingSkipTappedUnique, unique: true)
    }

    func measureOnboardingIntroImpression() {
        fire(event: .onboardingIntroShownUnique, unique: true)
        fireSharedPixel(.welcome(.shown))
    }

    func measureSetDefaultBrowserImpression() {
        fire(event: .onboardingIntroComparisonChartShownUnique, unique: true)
        fireSharedPixel(.setDefault(.shown))
    }

    func measureChooseBrowserCTAAction() {
        fire(event: .onboardingIntroChooseBrowserCTAPressed, unique: false)
        fireSharedPixel(.setDefault(.clicked(.engage)))
    }

    func measureAiIntroImpression() {
        fireSharedPixel(.aiIntro(.shown))
    }

    func measureAiIntroCTAAction() {
        fireSharedPixel(.aiIntro(.clicked(.engage)))
    }

    func measureChooseAppIconImpression() {
        fire(event: .onboardingIntroChooseAppIconImpressionUnique, unique: true)
        fireSharedPixel(.appIconColor(.shown))
    }

    func measureChooseAppIconColor(_ color: AppIcon) {
        if color != .defaultAppIcon {
            fire(event: .onboardingIntroChooseCustomAppIconColorCTAPressed, unique: false)
        }
        fireSharedPixel(.appIconColor(.clicked(color.pixelValue)))
    }

    func measureAddressBarPositionSelectionImpression() {
        fire(event: .onboardingIntroChooseAddressBarImpressionUnique, unique: true)
        fireSharedPixel(.addressBarPosition(.shown))
    }

    func measureChooseAddressBarPosition(_ position: AddressBarPosition) {
        switch position {
        case .top:
            fireSharedPixel(.addressBarPosition(.clicked(.top)))
        case .bottom:
            fire(event: .onboardingIntroBottomAddressBarSelected, unique: false)
            fireSharedPixel(.addressBarPosition(.clicked(.bottom)))
        }
    }

    func measureSearchExperienceSelectionImpression() {
        fire(event: .onboardingIntroChooseSearchExperienceImpressionUnique, unique: true)
        fireSharedPixel(.searchExperience(.shown))
    }

    func measureChooseAIChat() {
        fire(event: .onboardingIntroAIChatSelected, unique: false)
        fireSharedPixel(.searchExperience(.clicked(.searchPlusDuckAI)))
    }

    func measureChooseSearchOnly() {
        fire(event: .onboardingIntroSearchOnlySelected, unique: false)
        fireSharedPixel(.searchExperience(.clicked(.searchOnly)))
    }

    func measureDuckAIQuerySelectionImpression() {
        fire(event: .onboardingIntroDuckAIToggleImpressionUnique, unique: true)
        fireSharedPixel(.searchChatToggle(.shown))
    }

    func measureDuckAIQueryChooseSearchOnly() {
        fire(event: .onboardingIntroDuckAIToggleContinuePressedSearch, unique: false)
    }

    func measureDuckAIQueryChooseAIChat() {
        fire(event: .onboardingIntroDuckAIToggleContinuePressedAI, unique: false)
    }

    func measureDuckAIQuerySubmission(selection: DuckAIQueryMode, promptSource: DuckAIQueryPromptSource) {
        switch (promptSource, selection) {
        case (.custom, .duckAI):
            fireSharedPixel(.searchChatToggle(.clicked(.customChat)))
        case (.custom, .search):
            fireSharedPixel(.searchChatToggle(.clicked(.customSearch)))
        case (_, .duckAI):
            fireSharedPixel(.searchChatToggle(.clicked(.suggestedChat)))
        case (_, .search):
            fireSharedPixel(.searchChatToggle(.clicked(.suggestedSearch)))
        }
        setVariantIfNotAlreadySet(OnboardingPixelParameter.Variant(selection))
    }

    func measureSkipOnboardingScreenImpression() {
        fireSharedPixel(.skipOnboarding(.shown))
    }

    func measureSetDefaultBrowserSkipped() {
        fireSharedPixel(.setDefault(.clicked(.dismiss)))
    }

}

// MARK: - OnboardingPixelReporter + Custom Interaction

extension OnboardingPixelReporter: OnboardingCustomInteractionPixelReporting {

    func measureCustomSearch() {
        fire(event: .onboardingContextualSearchCustomUnique, unique: true)
        fireSharedPixel(.search(.clicked(.custom)))
    }
    
    func measureCustomSite() {
        fire(event: .onboardingContextualSiteCustomUnique, unique: true)
        fireSharedPixel(.visitSite(.clicked(.custom)))
    }
    
    func measureSecondSiteVisit() {
        if userDefaults.bool(forKey: siteVisitedUserDefaultsKey) {
            fire(event: .onboardingContextualSecondSiteVisitUnique, unique: true)
        } else {
            userDefaults.set(true, forKey: siteVisitedUserDefaultsKey)
        }
    }

    func measurePrivacyDashboardOpenedForFirstTime() {
        let daysSinceInstall = statisticsStore.installDate.flatMap { calendar.numberOfDaysBetween($0, and: dateProvider()) }
        let additionalParameters = [
            PixelParameters.fromOnboarding: "true",
            PixelParameters.daysSinceInstall: String(daysSinceInstall ?? 0)
        ]
        fire(event: .privacyDashboardFirstTimeOpenedUnique, unique: true, additionalParameters: additionalParameters)
    }

}

// MARK: - OnboardingPixelReporter + Screen Impression

extension OnboardingPixelReporter: OnboardingDaxDialogsReporting {

    func measureScreenImpression(event: Pixel.Event) {
        fire(event: event, unique: true)
    }

    func measureScreenImpression(_ event: OnboardingSharedPixelEvent) {
        if event == .end(.shown) || event == .endTryDuckAI(.shown) {
            downloadReasonExperimentMetric.measureDownloadReasonExperimentOnboardingCompleted()
        }

        fireSharedPixel(event)
    }

    func measureSearchResultsDialogGotItAction() {
        fireSharedPixel(.searchResults(.clicked(.engage)))
    }

    func measureTrackersDialogGotItAction() {
        fireSharedPixel(.trackersBlocked(.clicked(.engage)))
    }

    func measureSubscriptionPromoDialogShown() {
        fireSharedPixel(.subscriptionPromo(.shown))
    }

    func measureSubscriptionPromoEngageCTAAction() {
        fireSharedPixel(.subscriptionPromo(.clicked(.engage)))
    }

    func measureFireButtonOnboardingDeleteConfirmed() {
        fireSharedPixel(.fireButton(.clicked(.engage)))
    }

    func measureFireButtonOnboardingDismissButtonTapped() {
        fireSharedPixel(.fireButton(.clicked(.dismiss)))
    }

    func measureTrySearchDialogSuggestedSearchTapped() {
        fireSharedPixel(.search(.clicked(.suggested)))
    }

    func measureTrySearchDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingTrySearchDialogNewTabDismissButtonTapped, unique: false)
        fireSharedPixel(.search(.clicked(.dismiss)))
    }

    func measureSearchResultDialogDismissButtonTapped() {
        fire(event: .onboardingSearchResultDialogDismissButtonTapped, unique: false)
        fireSharedPixel(.searchResults(.clicked(.dismiss)))
    }

    func measureTryVisitSiteDialogSuggestedSiteTapped() {
        fireSharedPixel(.visitSite(.clicked(.suggested)))
    }

    func measureTryVisitSiteDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingTryVisitSiteDialogNewTabDismissButtonTapped, unique: false)
        fireSharedPixel(.visitSite(.clicked(.dismiss)))
    }

    func measureTryVisitSiteDialogDismissButtonTapped() {
        fire(event: .onboardingTryVisitSiteDialogDismissButtonTapped, unique: false)
        fireSharedPixel(.visitSite(.clicked(.dismiss)))
    }

    func measureTrackersDialogDismissButtonTapped() {
        fire(event: .onboardingTrackersDialogDismissButtonTapped, unique: false)
        fireSharedPixel(.trackersBlocked(.clicked(.dismiss)))
    }

    func measureFireDialogDismissButtonTapped() {
        fire(event: .onboardingFireDialogDismissButtonTapped, unique: false)
        fireSharedPixel(.fireButton(.clicked(.dismiss)))
    }

    func measureDuckAIFireButtonCTAAction() {
        fire(event: .onboardingDuckAIFireButtonCTAPressed, unique: false)
    }

    func measureDuckAIFireDialogImpression() {
        fire(event: .onboardingDuckAIFireDialogShownUnique, unique: true)
    }

    func measureDuckAIFinalDialogImpression() {
        fire(event: .onboardingDuckAIFinalDialogShownUnique, unique: true)
    }

    func measureDuckAIFinalDialogCTAAction() {
        fireSharedPixel(.end(.clicked(.engage)))
    }

    func measureEndOfJourneyDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingEndOfJourneyDialogNewTabDismissButtonTapped, unique: false)
        fireSharedPixel(.end(.clicked(.dismiss)))
    }

    func measureEndOfJourneyDialogDismissButtonTapped() {
        fire(event: .onboardingEndOfJourneyDialogDismissButtonTapped, unique: false)
        fireSharedPixel(.end(.clicked(.dismiss)))
    }

    func measureSubscriptionDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingSubscriptionDialogDismissButtonTapped, unique: false)
        fireSharedPixel(.subscriptionPromo(.clicked(.dismiss)))
    }

    func measureEndOfJourneyDialogCTAAction() {
        fire(event: .daxDialogsEndOfJourneyDismissed, unique: false)
        fireSharedPixel(.end(.clicked(.engage)))
    }

    func measureEndOfJourneyTryDuckAICTAAction() {
        fireSharedPixel(.endTryDuckAI(.clicked(.engage)))
    }

    func measureEndOfJourneyTryDuckAISkipAction() {
        fireSharedPixel(.endTryDuckAI(.clicked(.dismiss)))
    }

}

// MARK: - OnboardingPixelReporter + Add To Dock

extension OnboardingPixelReporter: OnboardingAddToDockReporting {
   
    func measureAddToDockPromoImpression() {
        fire(event: .onboardingAddToDockPromoImpressionsUnique, unique: true)
        fireSharedPixel(.addToDock(.shown))
    }
    
    func measureAddToDockPromoShowTutorialCTAAction() {
        fire(event: .onboardingAddToDockPromoShowTutorialCTATapped, unique: false)
        fireSharedPixel(.addToDock(.clicked(.engage)))
    }
    
    func measureAddToDockPromoDismissCTAAction() {
        fire(event: .onboardingAddToDockPromoDismissCTATapped, unique: false)
        fireSharedPixel(.addToDock(.clicked(.dismiss)))
    }
    
    func measureAddToDockTutorialDismissCTAAction() {
        fire(event: .onboardingAddToDockTutorialDismissCTATapped, unique: false)
    }

}

extension OnboardingPixelParameter.Variant {

    init(_ mode: DuckAIQueryMode) {
        switch mode {
        case .duckAI:
            self = .duckAIChat
        case .search:
            self = .duckAISearch
        }
    }

}

// MARK: - OnboardingPixelReporter + Download Reason Segmented Flow

extension OnboardingPixelReporter: OnboardingDownloadReasonPixelReporting {

    func measureDownloadReasonImpression() {
        fireSharedPixel(.downloadChoice(.shown))
    }

    func measureDownloadReasonSelection(_ reason: OnboardingDownloadReason) {
        fireSharedPixel(.downloadChoice(.clicked(.init(reason))))
        // Persist the chosen reason as the variant so every subsequent tailored-step pixel carries it.
        setVariantIfNotAlreadySet(OnboardingPixelParameter.Variant(reason))
        downloadReasonExperimentMetric.measureDownloadReasonSelected(reason)
    }

    func measureSearchPrivacySettingsImpression() {
        fireSharedPixel(.preferencesSerp(.shown))
    }

    func measureSearchPrivacySettingsSelection(recentlyVisitedSitesEnabled: Bool, safeSearchEnabled: Bool) {
        fireSharedPixel(.preferencesSerp(.clicked(recentlyVisitedSitesEnabled: recentlyVisitedSitesEnabled, safeSearchEnabled: safeSearchEnabled)))
    }

    func measureAIModelImpression() {
        fireSharedPixel(.preferencesAIModel(.shown))
    }

    func measureAIModelSelection(model: String) {
        fireSharedPixel(.preferencesAIModel(.clicked(model: model)))
    }

    func measureToggleInputModeImpression() {
        fireSharedPixel(.preferencesAIToggleMode(.shown))
    }

    func measureToggleInputModeSelection(openNewTabsWithAIChat: Bool) {
        fireSharedPixel(.preferencesAIToggleMode(.clicked(openNewTabsWithAIChat: openNewTabsWithAIChat)))
    }

    func measureAISearchSettingsImpression() {
        fireSharedPixel(.preferencesAISearch(.shown))
    }

    func measureAISearchSettingsSelection(searchAssistEnabled: Bool, aiGeneratedImagesEnabled: Bool) {
        fireSharedPixel(.preferencesAISearch(.clicked(searchAssistEnabled: searchAssistEnabled, aiGeneratedImagesEnabled: aiGeneratedImagesEnabled)))
    }

    func measureKeepDuckAIImpression() {
        fireSharedPixel(.preferencesDuckAI(.shown))
    }

    func measureKeepDuckAISelection(shouldKeep: Bool) {
        fireSharedPixel(.preferencesDuckAI(.clicked(shouldKeep ? .on : .off)))
    }

    func measureDuckPlayerImpression() {
        fireSharedPixel(.preferencesYoutube(.shown))
    }

    func measureDuckPlayerSelection(youTubeAdBlockingEnabled: Bool, duckPlayerEnabled: Bool) {
        fireSharedPixel(.preferencesYoutube(.clicked(youTubeAdBlockingEnabled: youTubeAdBlockingEnabled, duckPlayerEnabled: duckPlayerEnabled)))
    }

}

private extension OnboardingSharedPixelEvent.DownloadChoiceEvent.Value {

    init(_ reason: OnboardingDownloadReason) {
        switch reason {
        case .browserPrivately: self = .search
        case .privateAIChat: self = .aiChat
        case .noAI: self = .noAI
        case .blockAds: self = .adBlocking
        }
    }

}

// MARK: - OnboardingPixelReporter + OnboardingDownloadReasonExperiment

protocol ExperimentPixelFiring {
    /// Fires an experiment pixel with the specified parameters.
    ///
    /// - Parameters:
    ///   - subfeatureID: The unique identifier of the subfeature associated with the experiment.
    ///   - metric: The name of the metric being tracked (e.g., impressions, clicks, conversions).
    ///   - conversionWindowDays: The time range (in days) to associate the pixel with conversion events.
    ///   - value: A string representing the value associated with the metric, such as counts or statuses.
    static func fireExperimentPixel(for subfeatureID: SubfeatureID,
                                    metric: String,
                                    conversionWindowDays: ConversionWindow,
                                    value: String)
}

/// Conforming `PixelKit` to the `ExperimentPixelFiring` protocol.
///
/// `PixelKit` provides the concrete implementation for firing experiment pixels. By extending
/// `PixelKit` to conform to `ExperimentPixelFiring`, its functionality can be injected and mocked
/// for testing purposes.
extension PixelKit: ExperimentPixelFiring {}

struct OnboardingDownloadReasonExperimentMetric {
    private enum Name: String {
        case onboardingCompleted = "onboarding_completed"
        case downloadReasonSelectedSearch = "download_reason_selected_search"
        case downloadReasonSelectedAIChat = "download_reason_selected_ai-chat"
        case downloadReasonSelectedNoAI = "download_reason_selected_no-ai"
        case downloadReasonSelectedAdBlocking = "download_reason_selected_ad-blocking"
    }

    private static let conversionWindowD0: ConversionWindow = 0...0

    private let experimentPixelFiring: ExperimentPixelFiring.Type

    init(experimentPixelFiring: ExperimentPixelFiring.Type = PixelKit.self) {
        self.experimentPixelFiring = experimentPixelFiring
    }

    func measureDownloadReasonExperimentOnboardingCompleted() {
        fire(metric: .onboardingCompleted)
    }

    /// Fires the per-reason "selected" metric (one metric per option, empty value, d0) when the user
    /// picks a download reason.
    func measureDownloadReasonSelected(_ reason: OnboardingDownloadReason) {
        let metric: Name = switch reason {
        case .browserPrivately: .downloadReasonSelectedSearch
        case .privateAIChat: .downloadReasonSelectedAIChat
        case .noAI: .downloadReasonSelectedNoAI
        case .blockAds: .downloadReasonSelectedAdBlocking
        }
        fire(metric: metric)
    }

    private func fire(metric: Name) {
        experimentPixelFiring.fireExperimentPixel(
            for: iOSBrowserConfigSubfeature.onboardingFlowByDownloadReasonExperiment.rawValue,
            metric: metric.rawValue,
            conversionWindowDays: Self.conversionWindowD0,
            value: ""
        )
    }

}
