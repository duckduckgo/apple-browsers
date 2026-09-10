//
//  OnboardingIntroContentProvider.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Onboarding
import PrivacyConfig

// MARK: - Provider

protocol OnboardingIntroContentProviding {
    var landingContent: OnboardingLandingContent { get }
    var introStepContent: OnboardingIntroStepContent { get }
    var downloadReasonContent: OnboardingDownloadReasonContent { get }
    var serpPersonalizationContent: OnboardingPersonalizationContent { get }
    var aiModelPersonalizationContent: OnboardingAIModelContent { get }
    var addressBarToggleModePersonalizationContent: OnboardingAddressBarToggleModeContent { get }
    var aiSearchPersonalizationContent: OnboardingPersonalizationContent { get }
    var aiChatEnabledPersonalizationContent: OnboardingDuckAIEnabledPersonalizationContent { get }
    var adBlockingPersonalizationContent: OnboardingPersonalizationContent { get }
    var setDefaultBrowserContent: OnboardingComparisonContent { get }
    var aiIntroContent: OnboardingComparisonContent { get }
    var addToDockContent: OnboardingAddToDockContent { get }
    var appIconColorContent: OnboardingAppIconColorContent { get }
    var addressBarPositionContent: OnboardingAddressBarPositionContent { get }
    var searchExperienceContent: OnboardingSearchExperienceContent { get }
    var duckAIQueryContent: OnboardingDuckAIQueryContent { get }
}

struct OnboardingIntroContentProvider: OnboardingIntroContentProviding {
    private let flowType: OnboardingFlowType
    private let featureFlagger: FeatureFlagger
    private let searchExperienceProvider: OnboardingSearchExperienceProvider
    /// Resolves the user's selected download reason lazily. The reason is chosen mid-flow — after this provider is built — so it's read on demand.
    /// Defaults to `nil` (control arm and Duck.ai CPP flow).
    private let downloadReasonProvider: () -> OnboardingDownloadReason?

    init(
        flowType: OnboardingFlowType,
        featureFlagger: FeatureFlagger,
        searchExperienceProvider: OnboardingSearchExperienceProvider = OnboardingSearchExperience(),
        downloadReasonProvider: @escaping () -> OnboardingDownloadReason? = { nil }
    ) {
        self.flowType = flowType
        self.featureFlagger = featureFlagger
        self.searchExperienceProvider = searchExperienceProvider
        self.downloadReasonProvider = downloadReasonProvider
    }
}

// MARK: - Content Provider + Landing (Welcome to DuckDuckGo!)

struct OnboardingLandingContent: Equatable {
    let title: String
    let shouldShowDuckAIAnimation: Bool
}

extension OnboardingIntroContentProvider {

    var landingContent: OnboardingLandingContent {
        OnboardingLandingContent(
            title: UserText.onboardingWelcomeHeader,
            shouldShowDuckAIAnimation: flowType == .duckAI
        )
    }

}

// MARK: - Content Provider + Intro (Ready to...)

struct OnboardingIntroStepContent: Equatable {
    struct RestorePromptStepContent: Equatable {
        let title: String
        let message: String
        let primaryCTA: String
        let secondaryCTA: String
    }

    struct SkipFlowStepContent: Equatable {
        let title: String
        let message: String
        let primaryCTA: String
        let secondaryCTA: String
    }

    let title: String
    let message: String
    let primaryCTA: String
    let secondaryCTA: String
    let restorePromptStepContent: RestorePromptStepContent
    let skipFlowStepContent: SkipFlowStepContent
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var introStepContent: OnboardingIntroStepContent {
        let introMessage = switch flowType {
        case .default: UserText.Onboarding.Rebranding.Intro.message
        case .duckAI: UserText.Onboarding.DuckAICPP.Intro.message
        }

        let (skipMessage, skipPrimaryCTA) = switch flowType {
        case .default: (UserText.Onboarding.Skip.message, UserText.Onboarding.Skip.confirmSkipOnboardingCTA)
        case .duckAI: (UserText.Onboarding.DuckAICPP.Skip.message, UserText.Onboarding.DuckAICPP.Skip.confirmSkipOnboardingCTA)
        }

        let skipOnboardingContent = OnboardingIntroStepContent.SkipFlowStepContent(
            title: UserText.Onboarding.Skip.title,
            message: skipMessage,
            primaryCTA: skipPrimaryCTA,
            secondaryCTA: UserText.Onboarding.Skip.resumeOnboardingCTA
        )

        let restoreOnboardingContent = OnboardingIntroStepContent.RestorePromptStepContent(
            title: UserText.Onboarding.RestorePrompt.title,
            message: UserText.Onboarding.RestorePrompt.body,
            primaryCTA: UserText.Onboarding.RestorePrompt.restoreCTA,
            secondaryCTA: UserText.Onboarding.RestorePrompt.skipCTA
        )

        return OnboardingIntroStepContent(
            title: UserText.Onboarding.Rebranding.Intro.title,
            message: introMessage,
            primaryCTA: UserText.Onboarding.Intro.continueCTA,
            secondaryCTA: UserText.Onboarding.Intro.skipCTA,
            restorePromptStepContent: restoreOnboardingContent,
            skipFlowStepContent: skipOnboardingContent,
            daxAnimation: .thumbUp
        )
    }

}

// MARK: - Content Provider + Download Reason (Set things up your way)

struct OnboardingDownloadReasonContent: Equatable {
    /// Lottie pictograms in `OnboardingAnimations.xcassets/Pictograms`. Data assets get no
    /// generated symbol, so the raw value is the dataset name passed to `DotLottieFile.asset(named:)`.
    enum Animation: String {
        case search
        case duckAIChat = "duckai-chat"
        case noAI = "no-ai"
        case imageSweep = "image-sweep"
    }

    /// A selectable reason tile.
    struct Option: Hashable {
        let reason: OnboardingDownloadReason
        let animation: Animation
        let title: String
    }

    let title: String
    let message: String
    let options: [Option]
    let primaryCTA: String
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    /// Content for the Download Reason Screen.
    var downloadReasonContent: OnboardingDownloadReasonContent {
        OnboardingDownloadReasonContent(
            title: UserText.Onboarding.DownloadReason.title,
            message: UserText.Onboarding.DownloadReason.message,
            options: [
                .init(reason: .browserPrivately, animation: .search, title: UserText.Onboarding.DownloadReason.browsePrivately),
                .init(reason: .privateAIChat, animation: .duckAIChat, title: UserText.Onboarding.DownloadReason.chatWithAI),
                .init(reason: .noAI, animation: .noAI, title: UserText.Onboarding.DownloadReason.removeAI),
                .init(reason: .blockAds, animation: .imageSweep, title: UserText.Onboarding.DownloadReason.blockAds)
            ],
            primaryCTA: UserText.Onboarding.DownloadReason.cta,
            daxAnimation: .wingBottom
        )
    }

}

// MARK: - Personalization

struct OnboardingPersonalizationContent: Equatable {
    let title: String
    let message: String?
    let items: [Item]
    let primaryCTA: String
    let daxAnimation: DaxAnimation
    let footer: String?

    init(title: String, message: String?, items: [Item], primaryCTA: String, daxAnimation: DaxAnimation, footer: String? = nil) {
        self.title = title
        self.message = message
        self.items = items
        self.primaryCTA = primaryCTA
        self.daxAnimation = daxAnimation
        self.footer = footer
    }
}

extension OnboardingPersonalizationContent {

    struct Item: Hashable, Equatable {
        let type: ItemType
        let title: String
        let subtitle: String?
        /// Rows shown only while this item's toggle is on. Empty for standalone rows.
        let dependentItems: [Item]

        init(type: ItemType, title: String, subtitle: String?, dependentItems: [Item] = []) {
            self.type = type
            self.title = title
            self.subtitle = subtitle
            self.dependentItems = dependentItems
        }
    }

}

extension OnboardingPersonalizationContent.Item {

    enum ItemType: Equatable {
        case recentlyVisitedSites
        case safeSearch
        case searchAssist
        case aiGeneratedImages
        case youTubeAdBlocking
        case rejectOptionalCookies
        case acceptOtherCookies
    }

}

struct OnboardingAIModelContent: Equatable {
    let title: String
    let message: String
    let primaryCTA: String
    let daxAnimation: DaxAnimation
}

struct OnboardingAddressBarToggleModeContent: Equatable {
    let title: String
    let icon: OnboardingImageResource
    let footer: String
    let primaryCTA: String
    let secondaryCTA: String
    let daxAnimation: DaxAnimation?
}

struct OnboardingDuckAIEnabledPersonalizationContent: Equatable {
    let icon: OnboardingImageResource
    let title: String
    let message: String
    let primaryCTA: String
    let secondaryCTA: String
    let daxAnimation: DaxAnimation?
}

extension OnboardingIntroContentProvider {

    var serpPersonalizationContent: OnboardingPersonalizationContent {
        OnboardingPersonalizationContent(
            title: UserText.Onboarding.Personalization.Search.title,
            message: nil,
            items: [
                OnboardingPersonalizationContent.Item(type: .recentlyVisitedSites, title: UserText.Onboarding.Personalization.Search.recentlyVisitedSitesTitle, subtitle: UserText.Onboarding.Personalization.Search.recentlyVisitedSitesSubtitle),
                OnboardingPersonalizationContent.Item(type: .safeSearch, title: UserText.Onboarding.Personalization.Search.safeSearchTitle, subtitle: UserText.Onboarding.Personalization.Search.safeSearchSubtitle)
            ],
            primaryCTA: UserText.Onboarding.Personalization.Search.cta,
            daxAnimation: .wingLeft
        )
    }

    var aiModelPersonalizationContent: OnboardingAIModelContent {
        OnboardingAIModelContent(
            title: UserText.Onboarding.Personalization.AIModel.title,
            message: UserText.Onboarding.Personalization.AIModel.message,
            primaryCTA: UserText.Onboarding.Personalization.AIModel.cta,
            daxAnimation: .wingLeft
        )
    }

    var addressBarToggleModePersonalizationContent: OnboardingAddressBarToggleModeContent {
        OnboardingAddressBarToggleModeContent(
            title: UserText.Onboarding.Personalization.AddressBarToggle.title,
            icon: OnboardingImageResources.Personalization.addressBarToggleMode,
            footer: UserText.Onboarding.Personalization.AddressBarToggle.footer,
            primaryCTA: UserText.Onboarding.Personalization.AddressBarToggle.primaryCTA,
            secondaryCTA: UserText.Onboarding.Personalization.AddressBarToggle.secondaryCTA,
            daxAnimation: nil
        )
    }

    var aiSearchPersonalizationContent: OnboardingPersonalizationContent {
        OnboardingPersonalizationContent(
            title: UserText.Onboarding.Personalization.AISearch.title,
            message: nil,
            items: [
                OnboardingPersonalizationContent.Item(type: .searchAssist, title: UserText.Onboarding.Personalization.AISearch.searchAssistTitle, subtitle: UserText.Onboarding.Personalization.AISearch.searchAssistSubtitle),
                OnboardingPersonalizationContent.Item(type: .aiGeneratedImages, title: UserText.Onboarding.Personalization.AISearch.hideAIGeneratedImagesTitle, subtitle: UserText.Onboarding.Personalization.AISearch.hideAIGeneratedImagesSubtitle)
            ],
            primaryCTA: UserText.Onboarding.Personalization.AISearch.cta,
            daxAnimation: .wingLeft
        )
    }

    var aiChatEnabledPersonalizationContent: OnboardingDuckAIEnabledPersonalizationContent {
        OnboardingDuckAIEnabledPersonalizationContent(
            icon: OnboardingImageResources.Personalization.addressBarToggleMode,
            title: UserText.Onboarding.Personalization.DuckAIEnabled.title,
            message: UserText.Onboarding.Personalization.DuckAIEnabled.message,
            primaryCTA: UserText.Onboarding.Personalization.DuckAIEnabled.primaryCTA,
            secondaryCTA: UserText.Onboarding.Personalization.DuckAIEnabled.secondaryCTA,
            daxAnimation: nil
        )
    }

    var adBlockingPersonalizationContent: OnboardingPersonalizationContent {
        OnboardingPersonalizationContent(
            title: UserText.Onboarding.Personalization.AdBlocking.title,
            message: nil,
            items: [
                OnboardingPersonalizationContent.Item(type: .youTubeAdBlocking, title: UserText.Onboarding.Personalization.AdBlocking.adBlockingTitle, subtitle: nil),
                OnboardingPersonalizationContent.Item(
                    type: .rejectOptionalCookies,
                    title: UserText.Onboarding.Personalization.AdBlocking.rejectOptionalCookiesTitle,
                    subtitle: UserText.Onboarding.Personalization.AdBlocking.rejectOptionalCookiesSubtitle,
                    dependentItems: [
                        OnboardingPersonalizationContent.Item(
                            type: .acceptOtherCookies,
                            title: UserText.Onboarding.Personalization.AdBlocking.acceptOtherCookiesTitle,
                            subtitle: UserText.Onboarding.Personalization.AdBlocking.acceptOtherCookiesSubtitle
                        )
                    ]
                )
            ],
            primaryCTA: UserText.Onboarding.Personalization.AdBlocking.cta,
            daxAnimation: .wingLeft,
            footer: UserText.Onboarding.Personalization.AdBlocking.footer
        )
    }

}


// MARK: - Content Provider + Comparison Chart

struct OnboardingComparisonContent: Equatable {
    enum Competitor {
        case safari
        case google
        case ai
    }

    let title: String
    /// When set, renders as a text-and-icons table header; absent for icon-only headers.
    let subHeader: String?
    let competitor: Competitor
    let features: [RebrandedComparisonTableModel.Feature]
    let primaryCTA: String
    /// When set, renders a secondary skip button below the primary CTA.
    let secondaryCTA: String?
    let daxAnimation: DaxAnimation?
}

extension OnboardingIntroContentProvider {

    /// Non-tailored comparison content (No download reason, and Duck.ai CPP flow).
    private var defaultSetDefaultBrowserContent: OnboardingComparisonContent {
        let title = switch flowType {
        case .default: UserText.Onboarding.BrowsersComparison.title
        case .duckAI: UserText.Onboarding.DuckAICPP.BrowserComparison.title
        }

        return OnboardingComparisonContent(
            title: title,
            subHeader: nil,
            competitor: .safari,
            features: RebrandedComparisonTableModel.defaultBrowserFeatures,
            primaryCTA: UserText.Onboarding.BrowsersComparison.cta,
            secondaryCTA: UserText.onboardingSkip,
            daxAnimation: .wingBottom
        )
    }

    /// Content for the Set-as-Default comparison chart.
    ///
    /// Tailors the comparison table to the user's selected download reason (download-reason experiment).
    /// When no reason is set — control arm and Duck.ai CPP flow — the original content is returned.
    var setDefaultBrowserContent: OnboardingComparisonContent {
        // Return default version of comparison table if download reason is nil (Duck.ai + No experiment enrolled users)
        guard let reason = downloadReasonProvider() else { return defaultSetDefaultBrowserContent }

        let title = switch reason {
        case .browserPrivately, .privateAIChat:
            UserText.Onboarding.BrowsersComparison.titleGenericDownloadReasonExperiment
        case .noAI:
            UserText.Onboarding.BrowsersComparison.titleNoAIDownloadReasonExperiment
        case .blockAds:
            UserText.Onboarding.BrowsersComparison.titleNoAdsDownloadReasonExperiment
        }

        let subHeader = reason == .privateAIChat ? UserText.Onboarding.DuckAICPP.AIComparison.subHeader : nil

        let competitor: OnboardingComparisonContent.Competitor = switch reason {
        case .browserPrivately, .blockAds:
                .safari
        case .privateAIChat:
                .ai
        case .noAI:
                .google
        }

        return OnboardingComparisonContent(
            title: title,
            subHeader: subHeader,
            competitor: competitor,
            features: RebrandedComparisonTableModel.browserFeatures(for: reason),
            primaryCTA: UserText.Onboarding.BrowsersComparison.cta,
            secondaryCTA: UserText.onboardingSkip,
            daxAnimation: nil
        )
    }

    var aiIntroContent: OnboardingComparisonContent {
        OnboardingComparisonContent(
            title: UserText.Onboarding.DuckAICPP.AIComparison.title,
            subHeader: UserText.Onboarding.DuckAICPP.AIComparison.subHeader,
            competitor: .ai,
            features: RebrandedComparisonTableModel.defaultAIFeatures,
            primaryCTA: UserText.Onboarding.DuckAICPP.AIComparison.cta,
            secondaryCTA: nil,
            daxAnimation: .wingBottom
        )
    }

}

// MARK: - Content Provider + Add to Dock (Add me to your Dock!)

struct OnboardingAddToDockContent: Equatable {
    struct TutorialStepContent: Equatable {
        let title: String
        let message: String
        let primaryCTA: String
    }

    let title: String
    let message: String
    let primaryCTA: String
    let secondaryCTA: String
    let tutorialStepContent: TutorialStepContent
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var addToDockContent: OnboardingAddToDockContent {
        let promoMessage = switch flowType {
        case .default: UserText.AddToDockOnboarding.Promo.introMessageNew
        case .duckAI: UserText.Onboarding.DuckAICPP.AddToDock.Promo.message
        }

        let tutorial = OnboardingAddToDockContent.TutorialStepContent(
            title: UserText.AddToDockOnboarding.Tutorial.title,
            message: UserText.AddToDockOnboarding.Tutorial.message,
            primaryCTA: UserText.AddToDockOnboarding.Buttons.gotIt
        )

        return OnboardingAddToDockContent(
            title: UserText.AddToDockOnboarding.Promo.title,
            message: promoMessage,
            primaryCTA: UserText.AddToDockOnboarding.Buttons.tutorial,
            secondaryCTA: UserText.AddToDockOnboarding.Buttons.skip,
            tutorialStepContent: tutorial,
            daxAnimation: .wingLeft
        )
    }

}

// MARK: - Content Provider + App Icon Color (Which color looks best on me?)

struct OnboardingAppIconColorContent: Equatable {
    let title: String
    let message: String
    let primaryCTA: String
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var appIconColorContent: OnboardingAppIconColorContent {
        OnboardingAppIconColorContent(
            title: UserText.Onboarding.AppIconSelection.title,
            message: UserText.Onboarding.AppIconSelection.message,
            primaryCTA: UserText.Onboarding.AppIconSelection.cta,
            daxAnimation: .wingRight
        )
    }

}

// MARK: - Content Provider + Address Bar Position (Where should I put your address bar?)

struct OnboardingAddressBarPositionContent: Equatable {
    struct OptionContent: Equatable {
        let title: String
        let message: String
    }

    let title: String
    let topOption: OptionContent
    let bottomOption: OptionContent
    let defaultIndicator: String
    let primaryCTA: String
    let daxAnimation: DaxAnimation?
}

extension OnboardingIntroContentProvider {

    var addressBarPositionContent: OnboardingAddressBarPositionContent {
        OnboardingAddressBarPositionContent(
            title: UserText.Onboarding.AddressBarPosition.title,
            topOption: .init(
                title: UserText.Onboarding.AddressBarPosition.topTitle,
                message: UserText.Onboarding.AddressBarPosition.topMessage
            ),
            bottomOption: .init(
                title: UserText.Onboarding.AddressBarPosition.bottomTitle,
                message: UserText.Onboarding.AddressBarPosition.bottomMessage
            ),
            defaultIndicator: UserText.Onboarding.AddressBarPosition.defaultOption,
            primaryCTA: UserText.Onboarding.AddressBarPosition.cta,
            daxAnimation: nil // Dax-Floating is embedded in ScrollableOnboardingBackground
        )
    }

}

// MARK: - Content Provider + Search Experience (Want easy access to private AI chat in the address bar?)

struct OnboardingSearchExperienceContent: Equatable {
    let title: String
    let footer: AttributedString
    let primaryCTA: String
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var searchExperienceContent: OnboardingSearchExperienceContent {
        OnboardingSearchExperienceContent(
            title: UserText.Onboarding.SearchExperience.title,
            footer: AttributedString(UserText.Onboarding.SearchExperience.footerAttributed()),
            primaryCTA: UserText.Onboarding.SearchExperience.cta,
            daxAnimation: .wingLeft
        )
    }

}

// MARK: - Content Provider + Duck.ai Query Selection (Ready to get started?)

struct OnboardingDuckAIQueryContent: Equatable {
    let title: String
    let searchPlaceholder: String
    let aiPlaceholder: String
    /// Whether the Search / Duck.ai picker is shown.
    let isToggleVisible: Bool
    /// The pre-selected input when the picker is visible, or the only input when it's hidden.
    let defaultMode: DuckAIQueryMode
    let daxAnimation: DaxAnimation?
}

extension OnboardingIntroContentProvider {

    var duckAIQueryContent: OnboardingDuckAIQueryContent {
        let screen = duckAIQueryScreen
        return OnboardingDuckAIQueryContent(
            title: screen.title,
            searchPlaceholder: UserText.Onboarding.DuckAIQuery.searchPlaceholder,
            aiPlaceholder: UserText.Onboarding.DuckAIQuery.aiPlaceholder,
            isToggleVisible: screen.isToggleVisible,
            defaultMode: screen.defaultMode,
            daxAnimation: nil
        )
    }

    /// The Duck.ai query screen to present.
    /// The Duck.ai flow from CPP is fixed.
    /// The default flow branches on the download reason (see `defaultFlowDuckAIQueryScreen`).
    private var duckAIQueryScreen: DuckAIQueryScreen {
        switch flowType {
        case .default: defaultFlowDuckAIQueryScreen
        case .duckAI: .privateAIChat
        }
    }

    /// Default-flow branching:
    /// - `.privateAIChat` → the AI chat prompt (no picker visible).
    /// - `.browserPrivately, .noAI, .blockAds` show the AI toggle only if the user
    ///   turned the AI-chat search input on in the search experience screen, otherwise a search-only prompt.
    /// - not enrolled (`.none`) → the default combined prompt.
    private var defaultFlowDuckAIQueryScreen: DuckAIQueryScreen {
        switch downloadReasonProvider() {
        case .privateAIChat:
            return .privateAIChat
        case .browserPrivately, .noAI, .blockAds:
            return searchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding ? .searchOrAIChat : .privateSearch
        case .none:
            return .searchOrAIChat
        }
    }

}

/// A concrete Duck.ai query screen, owning its title and picker presentation.
private enum DuckAIQueryScreen {
    /// Search input only, no picker.
    case privateSearch
    /// Picker shown, pre-selecting Search.
    case searchOrAIChat
    /// AI input only, no picker.
    case privateAIChat

    var title: String {
        switch self {
        case .privateSearch: UserText.Onboarding.Personalization.DuckAIQuery.privateSearchTitle
        case .searchOrAIChat: UserText.Onboarding.DuckAIQuery.title
        case .privateAIChat: UserText.Onboarding.DuckAICPP.DuckAIQuery.title
        }
    }

    var isToggleVisible: Bool {
        switch self {
        case .searchOrAIChat: true
        case .privateSearch, .privateAIChat: false
        }
    }

    var defaultMode: DuckAIQueryMode {
        switch self {
        case .privateSearch, .searchOrAIChat: .search
        case .privateAIChat: .duckAI
        }
    }
}
