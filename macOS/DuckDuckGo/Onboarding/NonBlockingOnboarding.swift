//
//  NonBlockingOnboarding.swift
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

import FeatureFlags_macOS
import Foundation
import Persistence
import PrivacyConfig

struct NonBlockingOnboarding {

    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isNonBlocking: Bool {
        featureFlagger.isFeatureOn(.onboardingAsync)
            || OnboardingNonBlockingExperiment(featureFlagger: featureFlagger).isNonBlocking
    }

    /// First-run onboarding can be resumed without restarting contextual onboarding.
    func initializeContextualOnboarding(_ updater: ContextualOnboardingStateUpdater,
                                        persistor: NonBlockingOnboardingPersistor = NonBlockingOnboardingPersistor()) {
        guard isNonBlocking, !persistor.contextualInitialized else { return }
        updater.state = .notStarted
        persistor.contextualInitialized = true
    }
}

/// Durable onboarding progress, shared by the early and fully initialized page handlers.
final class NonBlockingOnboardingPersistor {
    enum Outcome: String {
        case completed
        case skipped
    }

    static let outcomeDidChange = Notification.Name("onboarding-experiment.outcome-did-change")

    private enum Key: String {
        case outcome = "onboarding-experiment.outcome"
        case contextualInitialized = "onboarding-experiment.contextual-initialized"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = Application.appDelegate.keyValueStore) {
        self.keyValueStore = keyValueStore
    }

    var contextualInitialized: Bool {
        get { (try? keyValueStore.object(forKey: Key.contextualInitialized.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.contextualInitialized.rawValue) }
    }

    var outcome: Outcome? {
        guard let value = try? keyValueStore.object(forKey: Key.outcome.rawValue) as? String else { return nil }
        return Outcome(rawValue: value)
    }

    /// Explicit debug reset starts a new first-run and contextual session.
    func reset() {
        try? keyValueStore.removeObject(forKey: Key.outcome.rawValue)
        try? keyValueStore.removeObject(forKey: Key.contextualInitialized.rawValue)
        NotificationCenter.default.post(name: Self.outcomeDidChange, object: nil)
    }

    @discardableResult
    func record(_ outcome: Outcome) -> Bool {
        guard self.outcome == nil else { return false }
        do {
            try keyValueStore.set(outcome.rawValue, forKey: Key.outcome.rawValue)
        } catch {
            return false
        }
        NotificationCenter.default.post(name: Self.outcomeDidChange, object: nil)
        return true
    }
}
