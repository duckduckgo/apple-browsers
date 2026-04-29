//
//  FreemiumPIREligibility.swift
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

import Core
import DataBrokerProtection_iOS
import PrivacyConfig
import Subscription

protocol FreemiumPIREligibilityChecking {
    func canShowEntryPoint() -> Bool
}

final class DefaultFreemiumPIREligibilityChecker: FreemiumPIREligibilityChecking {
    private let featureFlagger: FeatureFlagger
    private weak var runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
    private let subscriptionAuthenticationStateProvider: SubscriptionAuthenticationStateProvider

    init(featureFlagger: FeatureFlagger,
         runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?,
         subscriptionAuthenticationStateProvider: SubscriptionAuthenticationStateProvider) {
        self.featureFlagger = featureFlagger
        self.runPrerequisitesDelegate = runPrerequisitesDelegate
        self.subscriptionAuthenticationStateProvider = subscriptionAuthenticationStateProvider
    }

    func canShowEntryPoint() -> Bool {
        featureFlagger.isFeatureOn(.personalInformationRemoval)
            && featureFlagger.isFeatureOn(.dbpFreemiumPIR)
            && (runPrerequisitesDelegate?.meetsLocaleRequirement ?? false)
            && !subscriptionAuthenticationStateProvider.isUserAuthenticated
    }
}
