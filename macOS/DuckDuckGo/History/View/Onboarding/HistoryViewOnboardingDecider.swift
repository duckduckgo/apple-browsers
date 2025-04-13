//
//  HistoryViewOnboardingDecider.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit

protocol HistoryViewOnboardingDeciding {
    var shouldPresentOnboarding: Bool { get }
    func skipPresentingOnboarding()
}

final class HistoryViewOnboardingDecider: HistoryViewOnboardingDeciding {

    var shouldPresentOnboarding: Bool {
        featureFlagger.isFeatureOn(.historyView) && !isNewUser() && !settingsPersistor.didShowOnboardingView && isContextualOnboardingCompleted()
    }

    func skipPresentingOnboarding() {
        settingsPersistor.didShowOnboardingView = true
    }

    init(
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
        settingsPersistor: HistoryViewOnboardingViewSettingsPersisting = UserDefaultsHistoryViewOnboardingViewSettingsPersistor(),
        isContextualOnboardingCompleted: @escaping () -> Bool = { Application.appDelegate.onboardingContextualDialogsManager.state == .onboardingCompleted },
        isNewUser: @escaping () -> Bool = { AppDelegate.isNewUser }
    ) {
        self.featureFlagger = featureFlagger
        self.settingsPersistor = settingsPersistor
        self.isNewUser = isNewUser
        self.isContextualOnboardingCompleted = isContextualOnboardingCompleted
    }

    let featureFlagger: FeatureFlagger
    let settingsPersistor: HistoryViewOnboardingViewSettingsPersisting
    let isNewUser: () -> Bool
    let isContextualOnboardingCompleted: () -> Bool
}
