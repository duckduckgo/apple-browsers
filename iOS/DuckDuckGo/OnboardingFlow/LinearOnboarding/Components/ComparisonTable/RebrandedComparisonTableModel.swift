//
//  RebrandedComparisonTableModel.swift
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

import SwiftUI
import Onboarding
import DesignResourcesKitIcons

struct RebrandedComparisonTableModel {

    struct Feature: Equatable {
        let icon: Image
        let title: String
        let competitorAvailability: Availability
        let ddgAvailability: Availability

        enum Availability {
            case available
            case partial
            case unavailable

            var image: Image {
                switch self {
                case .available:
                    return OnboardingRebrandingImages.Comparison.availableIcon
                case .partial:
                    return OnboardingRebrandingImages.Comparison.partialIcon
                case .unavailable:
                    return OnboardingRebrandingImages.Comparison.unavailableIcon
                }
            }
        }
    }

}

// MARK: - Helpers

protocol OnboardingComparisonTableFeatureType {
    var title: String { get }
    var icon: Image { get }
}

extension RebrandedComparisonTableModel.Feature {

    init<T: OnboardingComparisonTableFeatureType>(type: T, competitorAvailability: Availability, ddgAvailability: Availability) {
        self.init(icon: type.icon, title: type.title, competitorAvailability: competitorAvailability, ddgAvailability: ddgAvailability)
    }
}


// MARK: - RebrandedComparisonTableModel + Browsers Comparison

extension RebrandedComparisonTableModel {

    static let defaultBrowserFeatures: [Feature] = [
        Feature(type: RebrandedComparisonTableModel.Feature.BrowserFeatureType.privateSearch, competitorAvailability: .unavailable, ddgAvailability: .available),
        Feature(type: RebrandedComparisonTableModel.Feature.BrowserFeatureType.privateAIChat, competitorAvailability: .unavailable, ddgAvailability: .available),
        Feature(type: RebrandedComparisonTableModel.Feature.BrowserFeatureType.blockTrackers, competitorAvailability: .partial, ddgAvailability: .available),
        Feature(type: RebrandedComparisonTableModel.Feature.BrowserFeatureType.blockCookiesAndAds, competitorAvailability: .unavailable, ddgAvailability: .available),
        Feature(type: RebrandedComparisonTableModel.Feature.BrowserFeatureType.blockYouTubeAds, competitorAvailability: .unavailable, ddgAvailability: .available),
    ]

}

extension RebrandedComparisonTableModel.Feature {

    enum BrowserFeatureType: Equatable, OnboardingComparisonTableFeatureType {
        case privateSearch
        case privateAIChat
        case blockTrackers
        case blockCookiesAndAds
        case blockYouTubeAds
        case eraseData

        var title: String {
            switch self {
            case .privateSearch:
                BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.privateSearch
            case .privateAIChat:
                BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.privateAIChat
            case .blockTrackers:
                BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.trackerBlockers
            case .blockCookiesAndAds:
                BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.cookiePopupsAndAds
            case .blockYouTubeAds:
                BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.duckplayer
            case .eraseData:
                BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.eraseBrowsingData
            }
        }

        var icon: Image {
            switch self {
            case .privateSearch:
                OnboardingRebrandingImages.Comparison.privateSearchIcon
            case .privateAIChat:
                OnboardingRebrandingImages.Comparison.privateAIChatIcon
            case .blockTrackers:
                OnboardingRebrandingImages.Comparison.shieldIcon
            case .blockCookiesAndAds:
                OnboardingRebrandingImages.Comparison.blockAdsIcon
            case .blockYouTubeAds:
                OnboardingRebrandingImages.Comparison.blockYouTubeAdsIcon
            case .eraseData:
                OnboardingRebrandingImages.Comparison.eraseDataIcon
            }
        }
    }

}

// MARK: - RebrandedComparisonTableModel + Download-Reason Comparison

//
// Feature lists for the Set-as-Default comparison chart when the user is enrolled in the
// download-reason experiment (`OnboardingFlowByDownloadReasonExperiment`).
// Each download reason shows a different, ordered list.
// - See: [Set-as-Default (Comparison Chart) step](https://app.asana.com/1/137249556945/task/1216445221863459?focus=true)
extension RebrandedComparisonTableModel {
    private typealias Icon = OnboardingRebrandingImages.Comparison
    private typealias BrowserText = BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features
    private typealias AIText = UserText.Onboarding.DuckAICPP.AIComparison.Features

    static func browserFeatures(for reason: OnboardingDownloadReason) -> [Feature] {
        switch reason {
        case .browserPrivately:
            return [
                Feature(icon: Icon.lensIcon, title: BrowserText.privateSearch, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.shieldIcon, title: BrowserText.trackerBlockers, competitorAvailability: .partial, ddgAvailability: .available),
                Feature(icon: Icon.eraseDataIcon, title: BrowserText.eraseBrowsingData, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.privateAIChatIcon, title: BrowserText.privateAIChat, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Image(uiImage: DesignSystemImages.Color.Size24.adsBlocked), title: BrowserText.cookiePopupsAndAds, competitorAvailability: .unavailable, ddgAvailability: .available),
            ]
        case .privateAIChat:
            return [
                Feature(icon: Image(""), title: AIText.anonymousChats, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.privateAIChatIcon, title: AIText.noAccountsNeeded, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.lockIcon, title: AIText.noTrainingData, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.aiIcon, title: AIText.onePlaceAccess, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.shieldIcon, title: BrowserText.privateWebSearch, competitorAvailability: .unavailable, ddgAvailability: .available),
            ]
        case .noAI:
            return [
                Feature(icon: Image(""), title: BrowserText.noAIAnswers, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Image(""), title: BrowserText.hideAIImages, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.privateSearchIcon, title: BrowserText.privateSearch, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.shieldIcon, title: BrowserText.trackerBlockers, competitorAvailability: .partial, ddgAvailability: .available),
                Feature(icon: Icon.blockAdsIcon, title: BrowserText.cookiePopupsAndAds, competitorAvailability: .unavailable, ddgAvailability: .available),
            ]
        case .blockAds:
            return [
                Feature(icon: Icon.blockAdsIcon, title: BrowserText.cookiePopupsAndAds, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.blockYouTubeAdsIcon, title: BrowserText.duckplayer, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.lensIcon, title: BrowserText.privateSearch, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.privateAIChatIcon, title: BrowserText.privateAIChat, competitorAvailability: .unavailable, ddgAvailability: .available),
                Feature(icon: Icon.shieldIcon, title: BrowserText.trackerBlockers, competitorAvailability: .partial, ddgAvailability: .available),
            ]
        }
    }
}

// MARK: - RebrandedComparisonTableModel + AI Comparison

extension RebrandedComparisonTableModel {

    static let defaultAIFeatures: [Feature] = [
        Feature(type: RebrandedComparisonTableModel.Feature.AIFeatureType.anonymousChats, competitorAvailability: .unavailable, ddgAvailability: .available),
        Feature(type: RebrandedComparisonTableModel.Feature.AIFeatureType.noAccountsNeeded, competitorAvailability: .unavailable, ddgAvailability: .available),
        Feature(type: RebrandedComparisonTableModel.Feature.AIFeatureType.noTrainingData, competitorAvailability: .unavailable, ddgAvailability: .available),
        Feature(type: RebrandedComparisonTableModel.Feature.AIFeatureType.onePlaceAccess, competitorAvailability: .unavailable, ddgAvailability: .available),
    ]

}

extension RebrandedComparisonTableModel.Feature {

    enum AIFeatureType: Equatable, OnboardingComparisonTableFeatureType {
        case anonymousChats
        case noAccountsNeeded
        case noTrainingData
        case onePlaceAccess

        var title: String {
            switch self {
            case .anonymousChats:
                UserText.Onboarding.DuckAICPP.AIComparison.Features.anonymousChats
            case .noAccountsNeeded:
                UserText.Onboarding.DuckAICPP.AIComparison.Features.noAccountsNeeded
            case .noTrainingData:
                UserText.Onboarding.DuckAICPP.AIComparison.Features.noTrainingData
            case .onePlaceAccess:
                UserText.Onboarding.DuckAICPP.AIComparison.Features.onePlaceAccess
            }
        }

        var icon: Image {
            switch self {
            case .anonymousChats:
                OnboardingRebrandingImages.Comparison.shieldIcon
            case .noAccountsNeeded:
                OnboardingRebrandingImages.Comparison.privateAIChatIcon
            case .noTrainingData:
                OnboardingRebrandingImages.Comparison.lockIcon
            case .onePlaceAccess:
                OnboardingRebrandingImages.Comparison.aiIcon
            }
        }
    }

}
