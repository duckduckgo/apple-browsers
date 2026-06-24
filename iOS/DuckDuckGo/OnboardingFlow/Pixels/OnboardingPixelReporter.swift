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
    func measureBrowserComparisonImpression()
    func measureChooseBrowserCTAAction()
    func measureAiComparisonImpression()
    func measureAiComparisonCTAAction()
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
    private let calendar: Calendar
    private let dateProvider: () -> Date
    private let userDefaults: UserDefaults
    private let sharedPixelHandler: OnboardingSharedPixelHandling
    private let sharedPixelsStorage: any KeyedStoring<OnboardingSharedPixelsKeys>
    private let siteVisitedUserDefaultsKey = "com.duckduckgo.ios.site-visited"

    init(
        pixel: OnboardingPixelFiring.Type = Pixel.self,
        uniquePixel: OnboardingPixelFiring.Type = UniquePixel.self,
        statisticsStore: StatisticsStore = StatisticsUserDefaults(),
        calendar: Calendar = .current,
        dateProvider: @escaping () -> Date = Date.init,
        userDefaults: UserDefaults = UserDefaults.app,
        sharedPixelHandler: OnboardingSharedPixelHandling? = nil,
        sharedPixelsStorage: (any KeyedStoring<OnboardingSharedPixelsKeys>)? = nil
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
    }

    private func fire(event: Pixel.Event, unique: Bool, additionalParameters: [String: String] = [:], includedParameters: [Pixel.QueryParameters] = [.appVersion]) {
        if unique {
            uniquePixel.fire(pixel: event, withAdditionalParameters: additionalParameters, includedParameters: includedParameters)
        } else {
            pixel.fire(pixel: event, withAdditionalParameters: additionalParameters, includedParameters: includedParameters)
        }
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
        }
    }
}

// MARK: - OnboardingPixelReporter + Intro

extension OnboardingPixelReporter: OnboardingIntroPixelReporting {

    func measureStartOnboardingCTAAction() {
        sharedPixelHandler.fire(.welcome(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureSkipOnboardingCTAAction() {
        fire(event: .onboardingIntroSkipOnboardingCTAPressed, unique: false)
        sharedPixelHandler.fire(.welcome(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureConfirmSkipOnboardingCTAAction() {
        fire(event: .onboardingIntroConfirmSkipOnboardingCTAPressed, unique: false)
        sharedPixelHandler.fire(.skipOnboarding(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureResumeOnboardingCTAAction() {
        fire(event: .onboardingIntroResumeOnboardingCTAPressed, unique: false)
        sharedPixelHandler.fire(.skipOnboarding(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
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
        sharedPixelHandler.fire(.welcome(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureBrowserComparisonImpression() {
        fire(event: .onboardingIntroComparisonChartShownUnique, unique: true)
        sharedPixelHandler.fire(.setDefault(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureChooseBrowserCTAAction() {
        fire(event: .onboardingIntroChooseBrowserCTAPressed, unique: false)
        sharedPixelHandler.fire(.setDefault(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureAiComparisonImpression() {
        sharedPixelHandler.fire(.aiComparison(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureAiComparisonCTAAction() {
        sharedPixelHandler.fire(.aiComparison(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureChooseAppIconImpression() {
        fire(event: .onboardingIntroChooseAppIconImpressionUnique, unique: true)
        sharedPixelHandler.fire(.appIconColor(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureChooseAppIconColor(_ color: AppIcon) {
        if color != .defaultAppIcon {
            fire(event: .onboardingIntroChooseCustomAppIconColorCTAPressed, unique: false)
        }
        sharedPixelHandler.fire(.appIconColor(.clicked(color.pixelValue)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureAddressBarPositionSelectionImpression() {
        fire(event: .onboardingIntroChooseAddressBarImpressionUnique, unique: true)
        sharedPixelHandler.fire(.addressBarPosition(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureChooseAddressBarPosition(_ position: AddressBarPosition) {
        switch position {
        case .top:
            sharedPixelHandler.fire(.addressBarPosition(.clicked(.top)),
                                    source: sharedPixelsStorage.onboardingSource,
                                    flow: sharedPixelsStorage.onboardingFlow)
        case .bottom:
            fire(event: .onboardingIntroBottomAddressBarSelected, unique: false)
            sharedPixelHandler.fire(.addressBarPosition(.clicked(.bottom)),
                                    source: sharedPixelsStorage.onboardingSource,
                                    flow: sharedPixelsStorage.onboardingFlow)
        }
    }

    func measureSearchExperienceSelectionImpression() {
        fire(event: .onboardingIntroChooseSearchExperienceImpressionUnique, unique: true)
        sharedPixelHandler.fire(.searchExperience(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureChooseAIChat() {
        fire(event: .onboardingIntroAIChatSelected, unique: false)
        sharedPixelHandler.fire(.searchExperience(.clicked(.searchPlusDuckAI)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureChooseSearchOnly() {
        fire(event: .onboardingIntroSearchOnlySelected, unique: false)
        sharedPixelHandler.fire(.searchExperience(.clicked(.searchOnly)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureDuckAIQuerySelectionImpression() {
        fire(event: .onboardingIntroDuckAIToggleImpressionUnique, unique: true)
        sharedPixelHandler.fire(.searchChatToggle(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
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
            sharedPixelHandler.fire(.searchChatToggle(.clicked(.customChat)),
                                    source: sharedPixelsStorage.onboardingSource,
                                    flow: sharedPixelsStorage.onboardingFlow)
        case (.custom, .search):
            sharedPixelHandler.fire(.searchChatToggle(.clicked(.customSearch)),
                                    source: sharedPixelsStorage.onboardingSource,
                                    flow: sharedPixelsStorage.onboardingFlow)
        case (_, .duckAI):
            sharedPixelHandler.fire(.searchChatToggle(.clicked(.suggestedChat)),
                                    source: sharedPixelsStorage.onboardingSource,
                                    flow: sharedPixelsStorage.onboardingFlow)
        case (_, .search):
            sharedPixelHandler.fire(.searchChatToggle(.clicked(.suggestedSearch)),
                                    source: sharedPixelsStorage.onboardingSource,
                                    flow: sharedPixelsStorage.onboardingFlow)
        }
        sharedPixelsStorage.onboardingVariant = OnboardingPixelParameter.Variant(selection)
    }

    func measureSkipOnboardingScreenImpression() {
        sharedPixelHandler.fire(.skipOnboarding(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

    func measureSetDefaultBrowserSkipped() {
        sharedPixelHandler.fire(.setDefault(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }

}

// MARK: - OnboardingPixelReporter + Custom Interaction

extension OnboardingPixelReporter: OnboardingCustomInteractionPixelReporting {

    func measureCustomSearch() {
        fire(event: .onboardingContextualSearchCustomUnique, unique: true)
        sharedPixelHandler.fire(.search(.clicked(.custom)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }
    
    func measureCustomSite() {
        fire(event: .onboardingContextualSiteCustomUnique, unique: true)
        sharedPixelHandler.fire(.visitSite(.clicked(.custom)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
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
        sharedPixelHandler.fire(event,
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureSearchResultsDialogGotItAction() {
        sharedPixelHandler.fire(.searchResults(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureTrackersDialogGotItAction() {
        sharedPixelHandler.fire(.trackersBlocked(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureSubscriptionPromoDialogShown() {
        sharedPixelHandler.fire(.subscriptionPromo(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureSubscriptionPromoEngageCTAAction() {
        sharedPixelHandler.fire(.subscriptionPromo(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureFireButtonOnboardingDeleteConfirmed() {
        sharedPixelHandler.fire(.fireButton(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureFireButtonOnboardingDismissButtonTapped() {
        sharedPixelHandler.fire(.fireButton(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureTrySearchDialogSuggestedSearchTapped() {
        sharedPixelHandler.fire(.search(.clicked(.suggested)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureTrySearchDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingTrySearchDialogNewTabDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.search(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureSearchResultDialogDismissButtonTapped() {
        fire(event: .onboardingSearchResultDialogDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.searchResults(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureTryVisitSiteDialogSuggestedSiteTapped() {
        sharedPixelHandler.fire(.visitSite(.clicked(.suggested)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureTryVisitSiteDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingTryVisitSiteDialogNewTabDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.visitSite(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureTryVisitSiteDialogDismissButtonTapped() {
        fire(event: .onboardingTryVisitSiteDialogDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.visitSite(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureTrackersDialogDismissButtonTapped() {
        fire(event: .onboardingTrackersDialogDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.trackersBlocked(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureFireDialogDismissButtonTapped() {
        fire(event: .onboardingFireDialogDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.fireButton(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
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
        sharedPixelHandler.fire(.end(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureEndOfJourneyDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingEndOfJourneyDialogNewTabDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.end(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureEndOfJourneyDialogDismissButtonTapped() {
        fire(event: .onboardingEndOfJourneyDialogDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.end(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureSubscriptionDialogNewTabDismissButtonTapped() {
        fire(event: .onboardingSubscriptionDialogDismissButtonTapped, unique: false)
        sharedPixelHandler.fire(.subscriptionPromo(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

    func measureEndOfJourneyDialogCTAAction() {
        fire(event: .daxDialogsEndOfJourneyDismissed, unique: false)
        sharedPixelHandler.fire(.end(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow,
                                variant: sharedPixelsStorage.onboardingVariant)
    }

}

// MARK: - OnboardingPixelReporter + Add To Dock

extension OnboardingPixelReporter: OnboardingAddToDockReporting {
   
    func measureAddToDockPromoImpression() {
        fire(event: .onboardingAddToDockPromoImpressionsUnique, unique: true)
        sharedPixelHandler.fire(.addToDock(.shown),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }
    
    func measureAddToDockPromoShowTutorialCTAAction() {
        fire(event: .onboardingAddToDockPromoShowTutorialCTATapped, unique: false)
        sharedPixelHandler.fire(.addToDock(.clicked(.engage)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
    }
    
    func measureAddToDockPromoDismissCTAAction() {
        fire(event: .onboardingAddToDockPromoDismissCTATapped, unique: false)
        sharedPixelHandler.fire(.addToDock(.clicked(.dismiss)),
                                source: sharedPixelsStorage.onboardingSource,
                                flow: sharedPixelsStorage.onboardingFlow)
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
