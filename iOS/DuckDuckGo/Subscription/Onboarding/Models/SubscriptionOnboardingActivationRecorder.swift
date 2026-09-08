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
    /// Whether the Duck.ai step was already recorded before this call.
    var isDuckAIActivated: Bool { get }
    /// Whether the PIR step was already recorded before this call.
    var isPIRActivated: Bool { get }
    /// Whether the VPN step was already recorded before this call.
    var isVPNActivated: Bool { get }
}

extension SubscriptionOnboardingActivationRecording {
    /// Records the activation and reports whether it was already recorded beforehand, so a caller that also
    /// fires a one-time experiment metric can guard it without risking the read/write ordering itself.
    @discardableResult
    func recordDuckAIActivatedIfNeeded() -> Bool {
        let wasAlreadyActivated = isDuckAIActivated
        recordDuckAIActivated()
        return wasAlreadyActivated
    }

    /// See `recordDuckAIActivatedIfNeeded()`.
    @discardableResult
    func recordPIRActivatedIfNeeded() -> Bool {
        let wasAlreadyActivated = isPIRActivated
        recordPIRActivated()
        return wasAlreadyActivated
    }

    /// See `recordDuckAIActivatedIfNeeded()`.
    @discardableResult
    func recordVPNActivatedIfNeeded() -> Bool {
        let wasAlreadyActivated = isVPNActivated
        recordVPNActivated()
        return wasAlreadyActivated
    }
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

    var isDuckAIActivated: Bool {
        SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completedItems.contains(.duckAI)
    }

    var isPIRActivated: Bool {
        SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completedItems.contains(.pir)
    }

    var isVPNActivated: Bool {
        SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completedItems.contains(.vpn)
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
    var isDuckAIActivated: Bool { false }
    var isPIRActivated: Bool { false }
    var isVPNActivated: Bool { false }
}
