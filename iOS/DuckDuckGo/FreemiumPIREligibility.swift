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
import Persistence
import PrivacyConfig
import Subscription

protocol FreemiumPIREligibilityChecking {
    func canShowEntryPoint() -> Bool
}

struct FreemiumPIRDebugSettings {

    private enum Key: String {
        case isEligibilityForced = "freemium-pir-debug-is-eligibility-forced"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var isEligibilityForced: Bool {
        (try? keyValueStore.object(forKey: Key.isEligibilityForced.rawValue) as? Bool) ?? false
    }

    func setEligibilityForced(_ isForced: Bool) {
        try? keyValueStore.set(isForced, forKey: Key.isEligibilityForced.rawValue)
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Key.isEligibilityForced.rawValue)
    }
}

final class DefaultFreemiumPIREligibilityChecker: FreemiumPIREligibilityChecking {
    private let featureFlagger: FeatureFlagger
    private weak var runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
    private let subscriptionAuthenticationStateProvider: SubscriptionAuthenticationStateProvider
    private let freemiumPIRDebugSettings: FreemiumPIRDebugSettings

    init(featureFlagger: FeatureFlagger,
         runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?,
         subscriptionAuthenticationStateProvider: SubscriptionAuthenticationStateProvider,
         freemiumPIRDebugSettings: FreemiumPIRDebugSettings) {
        self.featureFlagger = featureFlagger
        self.runPrerequisitesDelegate = runPrerequisitesDelegate
        self.subscriptionAuthenticationStateProvider = subscriptionAuthenticationStateProvider
        self.freemiumPIRDebugSettings = freemiumPIRDebugSettings
    }

    func canShowEntryPoint() -> Bool {
        guard featureFlagger.isFeatureOn(.personalInformationRemoval),
              !subscriptionAuthenticationStateProvider.isUserAuthenticated else {
            return false
        }

        // The debug override only bypasses rollout and locale gates; signed-in users still use paid PIR.
        if freemiumPIRDebugSettings.isEligibilityForced {
            return true
        }

        return featureFlagger.isFeatureOn(.dbpFreemiumPIR)
            && (runPrerequisitesDelegate?.meetsLocaleRequirement ?? false)
    }
}
