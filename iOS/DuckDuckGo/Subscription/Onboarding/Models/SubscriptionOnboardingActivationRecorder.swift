//
//  SubscriptionOnboardingActivationRecorder.swift
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

import Foundation
import Persistence

/// Records an activation the customer performed on their own, outside the onboarding flow.
///
/// Sections inside the flow report completion up to the flow, which writes it. A customer who activates a
/// feature by themselves has no flow running to report to, so these signals write to storage directly.
protocol SubscriptionOnboardingActivationRecording {
    /// Call when a prompt is submitted to a paid-tier model, which is what activates the Duck.ai step.
    func recordDuckAIActivated()
    /// Call when the customer has a PIR profile or has started a free scan.
    func recordPIRActivated()
    /// Call when the customer has a VPN configuration installed.
    func recordVPNActivated()
}

struct SubscriptionOnboardingActivationRecorder: SubscriptionOnboardingActivationRecording {

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    func recordDuckAIActivated() {
        markComplete(.duckAI)
    }

    func recordPIRActivated() {
        markComplete(.pir)
    }

    func recordVPNActivated() {
        markComplete(.vpn)
    }

    private func markComplete(_ item: SubscriptionOnboardingChecklistItem) {
        var persistor = SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore)
        persistor.markComplete(item)
    }
}

/// Records nothing, for callers with no onboarding progress to keep (tests, previews).
struct NullSubscriptionOnboardingActivationRecorder: SubscriptionOnboardingActivationRecording {
    func recordDuckAIActivated() {}
    func recordPIRActivated() {}
    func recordVPNActivated() {}
}
