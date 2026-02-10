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

    public enum Contextual {
        public static let tryASearchBackground = Image("Rebranding/contextual-bg-try-search", bundle: .module)
    }

    public enum Comparison {
        public static let safariIcon = Image("SafariBrowserIcon", bundle: .module)
        public static let ddgIcon = Image("DDGBrowserIcon", bundle: .module)
        public static let availableIcon = Image("Rebranding/Onboarding-Check", bundle: .module)
        public static let partialIcon = Image("Rebranding/Onboarding-Stop", bundle: .module)
        public static let unavailableIcon = Image("Rebranding/Onboarding-Cross", bundle: .module)
        public static let privateSearchIcon = Image("Rebranding/Comparison-PrivateSearch", bundle: .module)
        public static let blockTrackersIcon = Image("Rebranding/Comparison-BlockTrackers", bundle: .module)
        public static let blockCookiesIcon = Image("Rebranding/Comparison-BlockCookies", bundle: .module)
        public static let blockAdsIcon = Image("Rebranding/Comparison-BlockAds", bundle: .module)
        public static let eraseDataIcon = Image("Rebranding/Comparison-EraseData", bundle: .module)
    }

    public enum Rebranding {
        public static let duckDuckGoLogo = Image("Rebranding/DuckDuckGoLogo", bundle: .module)
    }

}

extension OnboardingRebranding {

    enum OnboardingImages {

        enum Contextual {
            static let tryASearchBackground = OnboardingRebrandingImages.Contextual.tryASearchBackground
        }

        enum Rebranding {
            static let duckDuckGoLogo = OnboardingRebrandingImages.Rebranding.duckDuckGoLogo
        }

    }

}
