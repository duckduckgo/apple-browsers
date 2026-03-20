//
//  OnboardingRebranding+Images.swift
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

public enum OnboardingRebrandingImages {

    public enum Linear {
        public static let introBackground = Image("Rebranding/linear-bg-intro", bundle: .module)
        public static let browsersComparisonBackground = Image("Rebranding/linear-bg-browsers-comparison", bundle: .module)
        public static let addToDockBackground = Image("Rebranding/linear-bg-add-to-dock", bundle: .module)
        public static let appIconColorSelectionBackground = Image("Rebranding/linear-bg-app-icon-color", bundle: .module)
        public static let addressBarPositionBackground = Image("Rebranding/linear-bg-address-bar-position", bundle: .module)
        public static let addressBarSearchPreferenceBackground = Image("Rebranding/linear-bg-address-bar-preference", bundle: .module)
    }

    public enum Contextual {
        public static let tryASearchBackground = Image("Rebranding/contextual-bg-try-search", bundle: .module)
        public static let tryASiteBackground = Image("Rebranding/contextual-bg-try-site", bundle: .module)
        public static let searchDoneBackground = Image("Rebranding/contextual-bg-search-done", bundle: .module)
        public static let trackerBlockedBackground = Image("Rebranding/contextual-bg-trackers", bundle: .module)
        public static let endOfJourneyBackground = Image("Rebranding/contextual-bg-end-of-journey", bundle: .module)
        public static let subscriptionPromoBackground = Image("Rebranding/contextual-bg-subscription-promo", bundle: .module)

        public static let promoShield = Image("Rebranding/shield", bundle: .module)
    }

    public enum Comparison {
        public static let safariIcon = Image("SafariBrowserIcon", bundle: .module)
        public static let ddgIcon = Image("DDGBrowserIcon", bundle: .module)
        public static let availableIcon = Image("Rebranding/Onboarding-Check", bundle: .module)
        public static let partialIcon = Image("Rebranding/Onboarding-Stop", bundle: .module)
        public static let unavailableIcon = Image("Rebranding/Onboarding-Cross", bundle: .module)
        public static let privateSearchIcon = Image("Rebranding/Comparison-PrivateSearch", bundle: .module)
        public static let privateAIChatIcon = Image("Rebranding/Comparison-PrivateAIChat", bundle: .module)
        public static let blockTrackersIcon = Image("Rebranding/Comparison-BlockTrackers", bundle: .module)
        public static let blockCookiesIcon = Image("Rebranding/Comparison-BlockCookies", bundle: .module)
        public static let blockAdsIcon = Image("Rebranding/Comparison-BlockAds", bundle: .module)
        public static let eraseDataIcon = Image("Rebranding/Comparison-EraseData", bundle: .module)
    }

    public enum SearchExperience {
        public static let searchOff = Image("Rebranding/OnboardingSearchOff", bundle: .module)
        public static let searchOn = Image("Rebranding/OnboardingSearchOn", bundle: .module)
        public static let searchAIOff = Image("Rebranding/OnboardingSearchAIOff", bundle: .module)
        public static let searchAIOn = Image("Rebranding/OnboardingSearchAIOn", bundle: .module)
    }

    public enum Branding {
        public static let duckDuckGoLogo = Image("Rebranding/DuckDuckGoLogo", bundle: .module)
    }

    public enum AddToDock {
        public static let promoBorder = Image("Rebranding/AddToDock-promo-border", bundle: .module)
        public static let tutorialBorder = Image("Rebranding/AddToDock-tutorial-border", bundle: .module)
    }
}
