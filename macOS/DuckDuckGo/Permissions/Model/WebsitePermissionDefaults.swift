//
//  WebsitePermissionDefaults.swift
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

import Combine
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

/// Reads and writes the default decision applied to a permission category when a website has no
/// saved decision of its own. `PermissionManager` consults this as the last step of its read path,
/// so a default takes effect in the prompt flow without any call site having to know about it.
protocol WebsitePermissionDefaultsProtocol: AnyObject {
    var availableDecisions: [PersistedPermissionDecision] { get }
    var fallbackDecision: PersistedPermissionDecision { get }
    /// Emits the effective default of every category whenever one changes, and on subscribe.
    var defaultsPublisher: AnyPublisher<[WebsitePermissionCategory: PersistedPermissionDecision], Never> { get }
    func defaultDecision(for category: WebsitePermissionCategory) -> PersistedPermissionDecision
    func setDefaultDecision(_ decision: PersistedPermissionDecision, for category: WebsitePermissionCategory)
}

final class WebsitePermissionDefaults: WebsitePermissionDefaultsProtocol {

    /// Every category offers the same two options. There is deliberately no "Always allow" default:
    /// a global grant would hand out camera, microphone or location without the user ever seeing a prompt.
    static let availableDecisions: [PersistedPermissionDecision] = [.ask, .deny]
    /// Used when nothing is stored, when the stored value can't be parsed, and whenever the feature
    /// flag is off — so a rollback restores exactly the pre-feature behaviour.
    static let fallbackDecision: PersistedPermissionDecision = .ask

    var availableDecisions: [PersistedPermissionDecision] { Self.availableDecisions }
    var fallbackDecision: PersistedPermissionDecision { Self.fallbackDecision }

    private let persistor: WebsitePermissionDefaultsStorage
    private let featureFlagger: FeatureFlagger
    private var storedDecisions: [WebsitePermissionCategory: PersistedPermissionDecision]
    private let subject: CurrentValueSubject<[WebsitePermissionCategory: PersistedPermissionDecision], Never>
    private var featureFlagCancellable: AnyCancellable?

    var defaultsPublisher: AnyPublisher<[WebsitePermissionCategory: PersistedPermissionDecision], Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(persistor: WebsitePermissionDefaultsStorage, featureFlagger: FeatureFlagger) {
        self.persistor = persistor
        self.featureFlagger = featureFlagger

        let stored = Self.loadDecisions(from: persistor)
        self.storedDecisions = stored
        let isEnabled = featureFlagger.isFeatureOn(.websitePermissionsSettings)
        self.subject = CurrentValueSubject(isEnabled ? stored : Self.disabledDecisions)

        // The flag is remotely releasable, so it can flip while the app is running.
        featureFlagCancellable = featureFlagger.updatesPublisher
            .sink { [weak self] in
                guard let self else { return }
                subject.send(effectiveDecisions)
            }
    }

    func defaultDecision(for category: WebsitePermissionCategory) -> PersistedPermissionDecision {
        guard isFeatureEnabled else { return Self.fallbackDecision }
        return storedDecisions[category] ?? Self.fallbackDecision
    }

    func setDefaultDecision(_ decision: PersistedPermissionDecision, for category: WebsitePermissionCategory) {
        guard isFeatureEnabled,
              Self.availableDecisions.contains(decision),
              storedDecisions[category] != decision
        else { return }

        storedDecisions[category] = decision
        persistor.setDecisionRawValue(decision.rawValue, for: category)
        subject.send(effectiveDecisions)
    }

    // MARK: - Private

    private var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.websitePermissionsSettings)
    }

    private var effectiveDecisions: [WebsitePermissionCategory: PersistedPermissionDecision] {
        isFeatureEnabled ? storedDecisions : Self.disabledDecisions
    }

    /// Every category mapped to the fallback, used while the feature flag is off.
    private static let disabledDecisions: [WebsitePermissionCategory: PersistedPermissionDecision] = {
        WebsitePermissionCategory.allCases.reduce(into: [:]) { $0[$1] = fallbackDecision }
    }()

    /// Loads a total map: a category with nothing stored, or an unrecognised or unsupported stored
    /// value, reads back as the fallback.
    private static func loadDecisions(
        from persistor: WebsitePermissionDefaultsStorage
    ) -> [WebsitePermissionCategory: PersistedPermissionDecision] {
        WebsitePermissionCategory.allCases.reduce(into: [:]) { decisions, category in
            let stored = persistor.decisionRawValue(for: category)
                .flatMap(PersistedPermissionDecision.init(rawValue:))
                .flatMap { availableDecisions.contains($0) ? $0 : nil }
            decisions[category] = stored ?? fallbackDecision
        }
    }
}
