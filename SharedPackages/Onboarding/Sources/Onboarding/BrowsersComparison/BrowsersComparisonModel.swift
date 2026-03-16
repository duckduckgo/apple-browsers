//
//  BrowsersComparisonModel.swift
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
import DesignResourcesKitIcons
import Common

public struct BrowsersComparisonModel {

    public static var privacyFeatures: [PrivacyFeature] {
        privacyFeatures(locale: .current)
    }

    public static func privacyFeatures(locale: Locale) -> [PrivacyFeature] {
        orderedFeatureTypes(locale: locale).map { featureType in
            PrivacyFeature(type: featureType, browsersSupport: browsersSupport(for: featureType))
        }
    }

    // For this iOS copy rollout, English users see an AI chat row in position 2 and the erase-data row removed.
    // All other locales/platforms keep the original feature order.
    private static func orderedFeatureTypes(locale: Locale) -> [PrivacyFeature.FeatureType] {
#if os(iOS)
        if isEnglishLanguage(locale: locale) {
            var featureTypes: [PrivacyFeature.FeatureType] = [
                .privateSearch,
                .privateAIChat,
                .blockThirdPartyTrackers,
                .blockCookiePopups,
                .blockCreepyAds
            ]
            return featureTypes
        }
#endif

        var featureTypes: [PrivacyFeature.FeatureType] = [
            .privateSearch,
            .blockThirdPartyTrackers,
            .blockCookiePopups,
            .blockCreepyAds,
            .eraseBrowsingData
        ]
#if os(macOS)
        featureTypes.append(.duckplayer)
#endif
        return featureTypes
    }

    private static func isEnglishLanguage(locale: Locale) -> Bool {
        locale.languageCode?.lowercased() == "en"
    }

    private static func browsersSupport(for feature: PrivacyFeature.FeatureType) -> [PrivacyFeature.BrowserSupport] {
        Browser.allCases.map { browser in
            let availability: PrivacyFeature.Availability
            switch feature {
            case .privateSearch:
                switch browser {
                case .ddg:
                    availability = .available
                case .safari:
                    availability = .unavailable
                }
            case .blockThirdPartyTrackers:
                switch browser {
                case .ddg:
                    availability = .available
                case .safari:
                    availability = .partiallyAvailable
                }
            case .blockCookiePopups:
                switch browser {
                case .ddg:
                    availability = .available
                case .safari:
                    availability = .unavailable
                }
            case .blockCreepyAds:
                switch browser {
                case .ddg:
                    availability = .available
                case .safari:
                    availability = .unavailable
                }
            case .privateAIChat:
                switch browser {
                case .ddg:
                    availability = .available
                case .safari:
                    availability = .unavailable
                }
            case .eraseBrowsingData:
                switch browser {
                case .ddg:
                    availability = .available
                case .safari:
                    availability = .unavailable
                }
            #if os(macOS)
            case .duckplayer:
                switch browser {
                case .ddg:
                    availability = .available
                case .safari:
                    availability = .unavailable
                }
            #endif
            }

            return PrivacyFeature.BrowserSupport(browser: browser, availability: availability)
        }
    }

}

// MARK: - Browser

extension BrowsersComparisonModel {

    enum Browser: CaseIterable {
        case safari
        case ddg

        var image: ImageResource {
            switch self {
            case .safari: .safariBrowserIcon
            case .ddg: .ddgBrowserIcon
            }
        }
    }

}

// MARK: - Privacy Feature

extension BrowsersComparisonModel {

    public struct PrivacyFeature {
        let type: FeatureType
        let browsersSupport: [BrowserSupport]
    }

}

extension BrowsersComparisonModel.PrivacyFeature {

    public struct UserText {
        public enum BrowsersComparison {
            public enum Features {
                public static let privateSearch = NSLocalizedString("onboarding.browsers.features.privateSearch.title", bundle: Bundle.module, value: "Search privately by default", comment: "Message to highlight browser capability of private searches")
                public static let trackerBlockers = NSLocalizedString("onboarding.highlights.browsers.features.trackerBlocker.title", bundle: Bundle.module, value: "Block 3rd-party trackers", comment: "Message to highlight browser capability of blocking 3rd-party trackers")
                public static let cookiePopups = NSLocalizedString("onboarding.highlights.browsers.features.cookiePopups.title", bundle: Bundle.module, value: "Block cookie pop-ups", comment: "Message to highlight how the browser allows you to block cookie pop-ups")
                public static let creepyAds = NSLocalizedString("onboarding.highlights.browsers.features.creepyAds.title", bundle: Bundle.module, value: "Block targeted ads", comment: "Message to highlight browser capability of blocking creepy ads")
                public static let eraseBrowsingData = NSLocalizedString("onboarding.highlights.browsers.features.eraseBrowsingData.title", bundle: Bundle.module, value: "Delete browsing data with one button", comment: "Message to highlight browser capability of swiftly erase browsing data")
                public static let privateAIChat = NotLocalizedString("onboarding.highlights.browsers.features.duckAI.title", value: "Use ChatGPT privately with Duck.ai built in", comment: "Message to highlight browser capability of chatting with ChatGPT without sharing data with third parties")
                public static let duckplayer = NSLocalizedString("onboarding.highlights.browsers.features.duckplayer.title", bundle: Bundle.module, value: "Play YouTube without targeted ads", comment: "Message to highlight browser capability of watching YouTube videos without targeted ads")
            }
        }
    }

    struct BrowserSupport {
        let browser: BrowsersComparisonModel.Browser
        let availability: Availability
    }

    public enum FeatureType: CaseIterable {
        case privateSearch
        case blockThirdPartyTrackers
        case blockCookiePopups
        case blockCreepyAds
        case privateAIChat
        case eraseBrowsingData
        #if os(macOS)
        case duckplayer
        #endif

        var title: String {
            switch self {
            case .privateSearch:
                UserText.BrowsersComparison.Features.privateSearch
            case .blockThirdPartyTrackers:
                UserText.BrowsersComparison.Features.trackerBlockers
            case .blockCookiePopups:
                UserText.BrowsersComparison.Features.cookiePopups
            case .blockCreepyAds:
                UserText.BrowsersComparison.Features.creepyAds
            case .privateAIChat:
                UserText.BrowsersComparison.Features.privateAIChat
            case .eraseBrowsingData:
                UserText.BrowsersComparison.Features.eraseBrowsingData
            #if os(macOS)
            case .duckplayer:
                UserText.BrowsersComparison.Features.duckplayer
            #endif
            }
        }

        var icon: DesignSystemImage {
            switch self {
            case .privateSearch:
                DesignSystemImages.Color.Size24.findSearch
            case .blockThirdPartyTrackers:
                DesignSystemImages.Color.Size24.shield
            case .blockCookiePopups:
                DesignSystemImages.Color.Size24.cookieBlocked
            case .blockCreepyAds:
                DesignSystemImages.Color.Size24.adsBlocked
            case .privateAIChat:
                DesignSystemImages.Glyphs.Size24.chat
            case .eraseBrowsingData:
                DesignSystemImages.Color.Size24.fire
            #if os(macOS)
            case .duckplayer:
                DesignSystemImages.Color.Size24.videoPlayer
            #endif
            }
        }
    }

    enum Availability: Identifiable {
        case available
        case partiallyAvailable
        case unavailable

        var id: Self {
            self
        }

        var image: ImageResource {
            switch self {
            case .available: .onboardingCheckDONOTUSE
            case .partiallyAvailable: .onboardingStopDONOTUSE
            case .unavailable: .onboardingCrossDONOTUSE
            }
        }
    }

}
