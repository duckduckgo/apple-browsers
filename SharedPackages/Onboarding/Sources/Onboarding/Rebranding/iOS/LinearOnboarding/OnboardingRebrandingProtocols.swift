//
//  OnboardingRebrandingProtocols.swift
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

#if os(iOS)
public extension OnboardingRebranding {

    public protocol ContextualDaxDialogDisabling {
        func disableContextualDaxDialogs()
    }

    public protocol OnboardingIntroImpressionReporting {
        func measureOnboardingIntroImpression()
    }

    public protocol OnboardingIntroPixelReporting: OnboardingIntroImpressionReporting {
        func measureSkipOnboardingCTAAction()
        func measureConfirmSkipOnboardingCTAAction()
        func measureResumeOnboardingCTAAction()
        func measureBrowserComparisonImpression()
        func measureChooseBrowserCTAAction()
        func measureChooseAppIconImpression()
        func measureChooseCustomAppIconColor()
        func measureAddressBarPositionSelectionImpression()
        func measureChooseBottomAddressBarPosition()
        func measureSearchExperienceSelectionImpression()
        func measureChooseAIChat()
        func measureChooseSearchOnly()
    }

    public protocol OnboardingAddToDockReporting {
        func measureAddToDockPromoImpression()
        func measureAddToDockPromoShowTutorialCTAAction()
        func measureAddToDockPromoDismissCTAAction()
        func measureAddToDockTutorialDismissCTAAction()
    }

    public typealias LinearOnboardingPixelReporting = OnboardingIntroPixelReporting & OnboardingAddToDockReporting
}
#endif
