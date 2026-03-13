//
//  RebrandedBrowsersComparisonModel.swift
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

struct RebrandedBrowsersComparisonModel {

    struct Feature: Equatable {
        let type: FeatureType
        let safariAvailability: Availability
        let ddgAvailability: Availability

        enum FeatureType: Equatable {
            case privateSearch
            case privateAIChat
            case blockTrackers
            case blockCookies
            case blockAds
            case eraseData

            var title: String {
                switch self {
                case .privateSearch:
                    return BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.privateSearch
                case .privateAIChat:
                    return BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.privateAIChatEnglish
                case .blockTrackers:
                    return BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.trackerBlockers
                case .blockCookies:
                    return BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.cookiePopups
                case .blockAds:
                    return BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.creepyAds
                case .eraseData:
                    return BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.eraseBrowsingData
                }
            }

            var icon: Image {
                switch self {
                case .privateSearch:
                    return OnboardingRebrandingImages.Comparison.privateSearchIcon
                case .privateAIChat:
                    return OnboardingRebrandingImages.Comparison.privateAIChatIcon
                case .blockTrackers:
                    return OnboardingRebrandingImages.Comparison.blockTrackersIcon
                case .blockCookies:
                    return OnboardingRebrandingImages.Comparison.blockCookiesIcon
                case .blockAds:
                    return OnboardingRebrandingImages.Comparison.blockAdsIcon
                case .eraseData:
                    return OnboardingRebrandingImages.Comparison.eraseDataIcon
                }
            }
        }

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

    static var features: [Feature] {
        features(locale: .current)
    }

    // English users see an AI chat row in position 2 and the erase-data row removed,
    // matching the logic in BrowsersComparisonModel.
    static func features(locale: Locale) -> [Feature] {
        if locale.languageCode?.lowercased() == "en" {
            return [
                Feature(type: .privateSearch, safariAvailability: .unavailable, ddgAvailability: .available),
                Feature(type: .privateAIChat, safariAvailability: .unavailable, ddgAvailability: .available),
                Feature(type: .blockTrackers, safariAvailability: .partial, ddgAvailability: .available),
                Feature(type: .blockCookies, safariAvailability: .unavailable, ddgAvailability: .available),
                Feature(type: .blockAds, safariAvailability: .unavailable, ddgAvailability: .available),
            ]
        }

        return [
            Feature(type: .privateSearch, safariAvailability: .unavailable, ddgAvailability: .available),
            Feature(type: .blockTrackers, safariAvailability: .partial, ddgAvailability: .available),
            Feature(type: .blockCookies, safariAvailability: .unavailable, ddgAvailability: .available),
            Feature(type: .blockAds, safariAvailability: .unavailable, ddgAvailability: .available),
            Feature(type: .eraseData, safariAvailability: .unavailable, ddgAvailability: .available),
        ]
    }
}
