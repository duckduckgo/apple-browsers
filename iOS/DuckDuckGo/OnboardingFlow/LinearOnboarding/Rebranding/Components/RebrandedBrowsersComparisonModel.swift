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
            case blockTrackers
            case blockCookies
            case blockAds
            case eraseData

            var title: String {
                switch self {
                case .privateSearch:
                    return "Search privately by default"
                case .blockTrackers:
                    return "Block 3rd-party trackers"
                case .blockCookies:
                    return "Block cookie requests & pop-ups"
                case .blockAds:
                    return "Block targeted ads"
                case .eraseData:
                    return "Erase browsing data swiftly"
                }
            }

            var icon: Image {
                switch self {
                case .privateSearch:
                    return OnboardingRebrandingImages.Comparison.privateSearchIcon
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

    static let features: [Feature] = [
        Feature(
            type: .privateSearch,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        ),
        Feature(
            type: .blockTrackers,
            safariAvailability: .partial,
            ddgAvailability: .available
        ),
        Feature(
            type: .blockCookies,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        ),
        Feature(
            type: .blockAds,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        ),
        Feature(
            type: .eraseData,
            safariAvailability: .unavailable,
            ddgAvailability: .available
        )
    ]
}
