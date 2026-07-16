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
    func measureSuggestionPressed()
    func measureDialogShown(dialogType: ContextualDialogType)
    func measureDialogDismissed(dialogType: ContextualDialogType)
    func measureDialogManuallyDismissed(dialogType: ContextualDialogType)
    func measureGotItPressed(dialogType: ContextualDialogType)
}

protocol OnboardingFireReporting: AnyObject {
    func measureFireButtonPressed()
    func measureFireDialogBurnAction()
    func measureFireDialogDismissed()
}

final class OnboardingPixelReporter {

    private weak var onboardingStateProvider: (ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater)?
    private let fire: (PixelKitEvent, PixelKit.Frequency) -> Void
    private let userDefaults: UserDefaults
    private let sharedPixelHandler: OnboardingSharedPixelHandling

    init(onboardingStateProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater
 = Application.appDelegate.onboardingContextualDialogsManager,
         userDefaults: UserDefaults = UserDefaults.standard,
         fireAction: @escaping (PixelKitEvent, PixelKit.Frequency) -> Void = { event, frequency in PixelKit.fire(event, frequency: frequency) },
         onboardingSharedPixelHandler: OnboardingSharedPixelHandling = OnboardingSharedPixelHandler(
            platform: .macOS,
            installTypeProvider: {
                DefaultReinstallUserDetection(keyValueStore: Application.appDelegate.keyValueStore).isReinstallingUser ? .reinstall : .newInstall
            },
            installDateProvider: { AppDelegate.firstLaunchDate }
         )) {
        self.onboardingStateProvider = onboardingStateProvider
        self.fire = fireAction
        self.userDefaults = userDefaults
        self.sharedPixelHandler = onboardingSharedPixelHandler
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
            sharedPixelHandler.fire(.search(.clicked(.custom)))
        }
        if onboardingStateProvider?.lastDialog == .tryASite {
            fire(ContextualOnboardingPixel.onboardingVisitSiteCustom, .uniqueByName)
            sharedPixelHandler.fire(.visitSite(.clicked(.custom)))
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

    func measureFireDialogBurnAction() {
        if onboardingStateProvider?.state != .onboardingCompleted {
            sharedPixelHandler.fire(.fireButton(.clicked(.engage)))
        }
    }

    func measureFireDialogDismissed() {
        if onboardingStateProvider?.state != .onboardingCompleted {
            sharedPixelHandler.fire(.fireButton(.clicked(.dismiss)))
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

    func measureDialogManuallyDismissed(dialogType: ContextualDialogType) {
        switch dialogType {
        case .tryASearch:
            sharedPixelHandler.fire(.search(.clicked(.dismiss)))
        case .searchDone:
            sharedPixelHandler.fire(.searchResults(.clicked(.dismiss)))
        case .tryASite:
            sharedPixelHandler.fire(.visitSite(.clicked(.dismiss)))
        case .trackers:
            sharedPixelHandler.fire(.trackersBlocked(.clicked(.dismiss)))
        case .tryFireButton:
            sharedPixelHandler.fire(.fireButton(.clicked(.dismiss)))
        case .highFive:
            sharedPixelHandler.fire(.end(.clicked(.dismiss)))
        }
    }

    func measureLastDialogShown() {
        fire(ContextualOnboardingPixel.onboardingFinished, .uniqueByName)
    }

    func measureFireButtonTryIt() {
        fire(ContextualOnboardingPixel.onboardingFireButtonTryItPressed, .uniqueByName)
    }

    func measureDialogShown(dialogType: ContextualDialogType) {
        switch dialogType {
        case .tryASearch:
            sharedPixelHandler.fire(.search(.shown))
        case .searchDone:
            sharedPixelHandler.fire(.searchResults(.shown))
        case .tryASite:
            sharedPixelHandler.fire(.visitSite(.shown))
        case .trackers:
            sharedPixelHandler.fire(.trackersBlocked(.shown))
        case .tryFireButton:
            sharedPixelHandler.fire(.fireButton(.shown))
        case .highFive:
            sharedPixelHandler.fire(.end(.shown))
        }
    }

    func measureGotItPressed(dialogType: ContextualDialogType) {
        switch dialogType {
        case .searchDone(let shouldFollowUp):
            sharedPixelHandler.fire(.searchResults(.clicked(.engage)))
            if shouldFollowUp {
                sharedPixelHandler.fire(.visitSite(.shown))
            }
        case .trackers(_, let shouldFollowUp):
            sharedPixelHandler.fire(.trackersBlocked(.clicked(.engage)))
            if shouldFollowUp {
                sharedPixelHandler.fire(.fireButton(.shown))
            }
        case .highFive:
            sharedPixelHandler.fire(.end(.clicked(.engage)))
        case .tryASearch,
                .tryASite,
                .tryFireButton:
            break
        }
    }

    func measureSuggestionPressed() {
        if onboardingStateProvider?.lastDialog == .tryASearch {
            sharedPixelHandler.fire(.search(.clicked(.suggested)))
        }
        if onboardingStateProvider?.lastDialog == .tryASite {
            sharedPixelHandler.fire(.visitSite(.clicked(.suggested)))
        }
    }
}
