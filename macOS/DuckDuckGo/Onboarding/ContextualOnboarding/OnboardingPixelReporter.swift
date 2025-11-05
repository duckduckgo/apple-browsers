//
//  OnboardingPixelReporter.swift
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
import Onboarding
import PixelKit

typealias OnboardingPixelReporting = OnboardingDialogsReporting & OnboardingAddressBarReporting

protocol OnboardingAddressBarReporting: AnyObject {
    func measureAddressBarTypedIn()
    func measurePrivacyDashboardOpened()
    func measureSiteVisited()
}

protocol OnboardingDialogsReporting: AnyObject {
    func measureLastDialogShown()
    func measureFireButtonTryIt()
    func measureDialogDismissed(dialogType: ContextualDialogType)
}

protocol OnboardingFireReporting: AnyObject {
    func measureFireButtonPressed()
}

final class OnboardingPixelReporter {

    private weak var onboardingStateProvider: (ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater)?
    private let fire: (PixelKitEvent, PixelKit.Frequency) -> Void
    private let userDefaults: UserDefaults

    init(onboardingStateProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater
 = Application.appDelegate.onboardingContextualDialogsManager,
         userDefaults: UserDefaults = UserDefaults.standard,
         fireAction: @escaping (PixelKitEvent, PixelKit.Frequency) -> Void = { event, frequency in PixelKit.fire(event, frequency: frequency) }) {
        self.onboardingStateProvider = onboardingStateProvider
        self.fire = fireAction
        self.userDefaults = userDefaults
    }
}

extension OnboardingPixelReporter: OnboardingAddressBarReporting {
    func measurePrivacyDashboardOpened() {
        if onboardingStateProvider?.state != .onboardingCompleted {
            fire(ContextualOnboardingPixel.onboardingPrivacyDashboardOpened, .uniqueByName)
        }
    }

    func measureAddressBarTypedIn() {
        if onboardingStateProvider?.lastDialog == .tryASearch {
            fire(ContextualOnboardingPixel.onboardingSearchCustom, .uniqueByName)
        }
        if onboardingStateProvider?.lastDialog == .tryASite {
            fire(ContextualOnboardingPixel.onboardingVisitSiteCustom, .uniqueByName)
        }
    }

    func measureSiteVisited() {
        let key = "onboarding.website-visited"
        let siteVisited = userDefaults.bool(forKey: key)
        if siteVisited {
            fire(ContextualOnboardingPixel.secondSiteVisited, .uniqueByName)
        } else {
            userDefaults.set(true, forKey: key)
        }
    }
}

extension OnboardingPixelReporter: OnboardingFireReporting {
    func measureFireButtonPressed() {
        if onboardingStateProvider?.state != .onboardingCompleted {
            fire(ContextualOnboardingPixel.onboardingFireButtonPressed, .uniqueByName)
        }
    }
}

extension OnboardingPixelReporter: OnboardingDialogsReporting {
    func measureDialogDismissed(dialogType: ContextualDialogType) {
        switch dialogType {
        case .tryASearch:
            fire(ContextualOnboardingPixel.trySearchDismissed, .uniqueByName)
        case .searchDone:
            fire(ContextualOnboardingPixel.searchResultDismissed, .uniqueByName)
        case .tryASite:
            fire(ContextualOnboardingPixel.tryVisitSiteDismissed, .uniqueByName)
        case .trackers:
            fire(ContextualOnboardingPixel.trackersBlockedDismissed, .uniqueByName)
        case .tryFireButton:
            fire(ContextualOnboardingPixel.tryFireButtonDismissed, .uniqueByName)
        case .highFive:
            fire(ContextualOnboardingPixel.finalDialogDismissed, .uniqueByName)
        }
    }

    func measureLastDialogShown() {
        fire(ContextualOnboardingPixel.onboardingFinished, .uniqueByName)
    }

    func measureFireButtonTryIt() {
        fire(ContextualOnboardingPixel.onboardingFireButtonTryItPressed, .uniqueByName)
    }
}
