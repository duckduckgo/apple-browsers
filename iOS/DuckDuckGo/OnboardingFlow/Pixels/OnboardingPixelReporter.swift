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
import PixelKit
import PixelExperimentKit

/// A protocol that defines a method for firing experiment-related analytics pixels.
///
/// Types conforming to this protocol can be used to send experiment data (e.g., metrics and user actions).
/// This protocol is particularly useful for injecting dependencies to enable testing.
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
    func measureSkipOnboardingCTAAction()
    func measureConfirmSkipOnboardingCTAAction()
    func measureResumeOnboardingCTAAction()
    func measureAutoRestoreOnboardingPromptShown()
    func measureAutoRestoreOnboardingRestoreCTAAction()
    func measureAutoRestoreOnboardingSkipCTAAction()
    func measureBrowserComparisonImpression()
    func measureChooseBrowserCTAAction()
    func measureChooseAppIconImpression()
    func measureChooseCustomAppIconColor()
    func measureAddressBarPositionSelectionImpression()
    func measureChooseBottomAddressBarPosition()
    func measureSearchExperienceSelectionImpression()
    func measureChooseAIChat()
    func measureChooseSearchOnly()
    func measureDuckAIQueryExperimentSelectionImpression()
    func measureDuckAIQueryExperimentChooseSearchOnly()
    func measureDuckAIQueryExperimentChooseAIChat()
    func measureDuckAIQueryExperimentQuerySubmission(selection: DuckAIQueryExperimentMode, promptSource: DuckAIQueryExperimentPromptSource)
}


protocol OnboardingCustomInteractionPixelReporting {
    func measureCustomSearch()
    func measureCustomSite()
    func measureSecondSiteVisit()
    func measurePrivacyDashboardOpenedForFirstTime()
}

protocol OnboardingDaxDialogsReporting {
    func measureScreenImpression(event: Pixel.Event)
    func measureTrySearchDialogNewTabDismissButtonTapped()
    func measureSearchResultDialogDismissButtonTapped()
    func measureTryVisitSiteDialogNewTabDismissButtonTapped()
    func measureTryVisitSiteDialogDismissButtonTapped()
    func measureTrackersDialogDismissButtonTapped()
    func measureFireDialogDismissButtonTapped()
    func measureDuckAIExperimentFireButtonCTAAction()
    func measureDuckAIExperimentFinalDialogImpression()
    func measureEndOfJourneyDialogNewTabDismissButtonTapped()
    func measureEndOfJourneyDialogDismissButtonTapped()
    func measureSubscriptionDialogNewTabDismissButtonTapped()
    func measureEndOfJourneyDialogCTAAction()
}


protocol OnboardingAddToDockReporting {
    func measureAddToDockPromoImpression()
    func measureAddToDockPromoShowTutorialCTAAction()
    func measureAddToDockPromoDismissCTAAction()
    func measureAddToDockTutorialDismissCTAAction()
}

typealias LinearOnboardingPixelReporting = OnboardingIntroPixelReporting & OnboardingAddToDockReporting
typealias OnboardingPixelReporting = LinearOnboardingPixelReporting & OnboardingCustomInteractionPixelReporting & OnboardingDaxDialogsReporting

// MARK: - Implementation

final class OnboardingPixelReporter {
    private let pixel: OnboardingPixelFiring.Type
    private let uniquePixel: OnboardingPixelFiring.Type
    private let statisticsStore: StatisticsStore
    private let experimentPixel: ExperimentPixelFiring.Type
    private let calendar: Calendar
    private let dateProvider: () -> Date
    private let userDefaults: UserDefaults
    private let siteVisitedUserDefaultsKey = "com.duckduckgo.ios.site-visited"

    init(
        pixel: OnboardingPixelFiring.Type = Pixel.self,
        uniquePixel: OnboardingPixelFiring.Type = UniquePixel.self,
        experimentPixel: ExperimentPixelFiring.Type = PixelKit.self,
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        calendar: Calendar = .current,
        dateProvider: @escaping () -> Date = Date.init,
        userDefaults: UserDefaults = UserDefaults.app
    ) {
        self.pixel = pixel
        self.uniquePixel = uniquePixel
        self.experimentPixel = experimentPixel
        self.statisticsStore = statisticsStore
        self.calendar = calendar
        self.dateProvider = dateProvider
        self.userDefaults = userDefaults
    }

    private func fire(event: Pixel.Event, unique: Bool, additionalParameters: [String: String] = [:], includedParameters: [Pixel.QueryParameters] = [.appVersion]) {
        if unique {
            uniquePixel.fire(pixel: event, withAdditionalParameters: additionalParameters, includedParameters: includedParameters)
        } else {
            pixel.fire(pixel: event, withAdditionalParameters: additionalParameters, includedParameters: includedParameters)
        }
    }

}

enum DuckAIQueryExperimentPromptSource: String {
    case custom
    case option1
    case option2
    case option3
}

// MARK: - OnboardingPixelReporter + Intro

extension OnboardingPixelReporter: OnboardingIntroPixelReporting {
    private enum DuckAIQueryExperimentMetric {
        enum Name: String {
            case search = "search_type"
            case aiChat = "aichat_type"
            case screenImpression = "screen-impression"
            case ctaPressed = "cta-pressed"
        }
        enum ScreenImpressionValue: String {
            case toggleScreen = "toggle-screen"
            case fireDialog = "fire-dialog"
            case finalDialog = "final-dialog"
        }
        enum CTAPressedValue: String {
            case continuePressedSearch = "toggle-continue-pressed_search"
            case continuePressedAI = "toggle-continue-pressed_ai"
            case fireButtonPressed = "fire-button-pressed"
        }
        static let conversionWindowD0: ConversionWindow = 0...0
        static let conversionWindowD7: ConversionWindow = 0...7
    }

    private func fireExperimentScreenImpressionPixel(value: DuckAIQueryExperimentMetric.ScreenImpressionValue) {
        for window in [DuckAIQueryExperimentMetric.conversionWindowD0, DuckAIQueryExperimentMetric.conversionWindowD7] {
            experimentPixel.fireExperimentPixel(
                for: AIChatSubfeature.onboardingDuckAIQueryExperiment.rawValue,
                metric: DuckAIQueryExperimentMetric.Name.screenImpression.rawValue,
                conversionWindowDays: window,
                value: value.rawValue
            )
        }
    }

    private func fireExperimentCTAPressedPixel(value: DuckAIQueryExperimentMetric.CTAPressedValue) {
        for window in [DuckAIQueryExperimentMetric.conversionWindowD0, DuckAIQueryExperimentMetric.conversionWindowD7] {
            experimentPixel.fireExperimentPixel(
                for: AIChatSubfeature.onboardingDuckAIQueryExperiment.rawValue,
                metric: DuckAIQueryExperimentMetric.Name.ctaPressed.rawValue,
                conversionWindowDays: window,
                value: value.rawValue
            )
        }
    }

    func measureSkipOnboardingCTAAction() {
        fire(event: .onboardingIntroSkipOnboardingCTAPressed, unique: false)
    }

    func measureConfirmSkipOnboardingCTAAction() {
        fire(event: .onboardingIntroConfirmSkipOnboardingCTAPressed, unique: false)
    }

    func measureResumeOnboardingCTAAction() {
        fire(event: .onboardingIntroResumeOnboardingCTAPressed, unique: false)
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
    }

    func measureBrowserComparisonImpression() {
        fire(event: .onboardingIntroComparisonChartShownUnique, unique: true)
    }

    func measureChooseBrowserCTAAction() {
        fire(event: .onboardingIntroChooseBrowserCTAPressed, unique: false)
    }

    func measureChooseAppIconImpression() {
        fire(event: .onboardingIntroChooseAppIconImpressionUnique, unique: true)
    }

    func measureChooseCustomAppIconColor() {
        fire(event: .onboardingIntroChooseCustomAppIconColorCTAPressed, unique: false)
    }

    func measureAddressBarPositionSelectionImpression() {
        fire(event: .onboardingIntroChooseAddressBarImpressionUnique, unique: true)
    }

    func measureChooseBottomAddressBarPosition() {
        fire(event: .onboardingIntroBottomAddressBarSelected, unique: false)
    }

    func measureSearchExperienceSelectionImpression() {
        fire(event: .onboardingIntroChooseSearchExperienceImpressionUnique, unique: true)
    }

    func measureChooseAIChat() {
        fire(event: .onboardingIntroAIChatSelected, unique: false)
    }

    func measureChooseSearchOnly() {
        fire(event: .onboardingIntroSearchOnlySelected, unique: false)
    }

    func measureDuckAIQueryExperimentSelectionImpression() {
        fire(event: .onboardingIntroDuckAIExperimentToggleImpressionUnique, unique: true)
        fireExperimentScreenImpressionPixel(value: .toggleScreen)
    }

    func measureDuckAIQueryExperimentChooseSearchOnly() {
        fire(event: .onboardingIntroDuckAIExperimentToggleContinuePressedSearch, unique: false)
        fireExperimentCTAPressedPixel(value: .continuePressedSearch)
    }

    func measureDuckAIQueryExperimentChooseAIChat() {
        fire(event: .onboardingIntroDuckAIExperimentToggleContinuePressedAI, unique: false)
        fireExperimentCTAPressedPixel(value: .continuePressedAI)
    }

    func measureDuckAIQueryExperimentQuerySubmission(selection: DuckAIQueryExperimentMode, promptSource: DuckAIQueryExperimentPromptSource) {
        let metricName: DuckAIQueryExperimentMetric.Name
        switch selection {
        case .duckAI:
            metricName = .aiChat
        case .search:
            metricName = .search
        }

        for window in [DuckAIQueryExperimentMetric.conversionWindowD0, DuckAIQueryExperimentMetric.conversionWindowD7] {
            experimentPixel.fireExperimentPixel(
                for: AIChatSubfeature.onboardingDuckAIQueryExperiment.rawValue,
                metric: metricName.rawValue,
                conversionWindowDays: window,
                value: promptSource.rawValue
            )
        }
    }

}

// MARK: - OnboardingPixelReporter + Custom Interaction

extension OnboardingPixelReporter: OnboardingCustomInteractionPixelReporting {

    func measureCustomSearch() {
        fire(event: .onboardingContextualSearchCustomUnique, unique: true)
    }
    
    func measureCustomSite() {
        fire(event: .onboardingContextualSiteCustomUnique, unique: true)
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
        if case .onboardingDuckAIExperimentFireDialogShownUnique = event {
            fireExperimentScreenImpressionPixel(value: .fireDialog)
        }
    }

    func measureTrySearchDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingTrySearchDialogNewTabDismissButtonTapped, unique: false)
    }

    func measureSearchResultDialogDismissButtonTapped() {
        fire(event: .onboardingSearchResultDialogDismissButtonTapped, unique: false)
    }

    func measureTryVisitSiteDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingTryVisitSiteDialogNewTabDismissButtonTapped, unique: false)
    }

    func measureTryVisitSiteDialogDismissButtonTapped() {
        fire(event: .onboardingTryVisitSiteDialogDismissButtonTapped, unique: false)
    }

    func measureTrackersDialogDismissButtonTapped() {
        fire(event: .onboardingTrackersDialogDismissButtonTapped, unique: false)
    }

    func measureFireDialogDismissButtonTapped() {
        fire(event: .onboardingFireDialogDismissButtonTapped, unique: false)
    }

    func measureDuckAIExperimentFireButtonCTAAction() {
        fire(event: .onboardingDuckAIExperimentFireButtonCTAPressed, unique: false)
        fireExperimentCTAPressedPixel(value: .fireButtonPressed)
    }

    func measureDuckAIExperimentFinalDialogImpression() {
        fire(event: .onboardingDuckAIExperimentFinalDialogShownUnique, unique: true)
        fireExperimentScreenImpressionPixel(value: .finalDialog)
    }

    func measureEndOfJourneyDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingEndOfJourneyDialogNewTabDismissButtonTapped, unique: false)
    }

    func measureEndOfJourneyDialogDismissButtonTapped() {
        fire(event: .onboardingEndOfJourneyDialogDismissButtonTapped, unique: false)
    }

    func measureSubscriptionDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingSubscriptionDialogDismissButtonTapped, unique: false)
    }

    func measureEndOfJourneyDialogCTAAction() {
        fire(event: .daxDialogsEndOfJourneyDismissed, unique: false)
    }

}

// MARK: - OnboardingPixelReporter + Add To Dock

extension OnboardingPixelReporter: OnboardingAddToDockReporting {
   
    func measureAddToDockPromoImpression() {
        fire(event: .onboardingAddToDockPromoImpressionsUnique, unique: true)
    }
    
    func measureAddToDockPromoShowTutorialCTAAction() {
        fire(event: .onboardingAddToDockPromoShowTutorialCTATapped, unique: false)
    }
    
    func measureAddToDockPromoDismissCTAAction() {
        fire(event: .onboardingAddToDockPromoDismissCTATapped, unique: false)
    }
    
    func measureAddToDockTutorialDismissCTAAction() {
        fire(event: .onboardingAddToDockTutorialDismissCTATapped, unique: false)
    }

}
