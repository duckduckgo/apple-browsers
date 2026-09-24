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

protocol WebsitePermissionDefaultsProtocol: AnyObject {
    var availableDecisions: [PersistedPermissionDecision] { get }
    var fallbackDecision: PersistedPermissionDecision { get }
    var defaultsPublisher: AnyPublisher<[WebsitePermissionCategory: PersistedPermissionDecision], Never> { get }
    func defaultDecision(for category: WebsitePermissionCategory) -> PersistedPermissionDecision
    func setDefaultDecision(_ decision: PersistedPermissionDecision, for category: WebsitePermissionCategory)
}

final class WebsitePermissionDefaults: WebsitePermissionDefaultsProtocol {

    let availableDecisions: [PersistedPermissionDecision] = [.ask, .deny]
    let fallbackDecision: PersistedPermissionDecision = .ask

    private let storage: WebsitePermissionDefaultsStorage
    private let featureFlagger: FeatureFlagger
    private var storedDecisions: [WebsitePermissionCategory: PersistedPermissionDecision]
    private let subject: CurrentValueSubject<[WebsitePermissionCategory: PersistedPermissionDecision], Never>
    private var featureFlagCancellable: AnyCancellable?

    var defaultsPublisher: AnyPublisher<[WebsitePermissionCategory: PersistedPermissionDecision], Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(storage: WebsitePermissionDefaultsStorage, featureFlagger: FeatureFlagger) {
        self.storage = storage
        self.featureFlagger = featureFlagger

        self.storedDecisions = [:]
        self.subject = CurrentValueSubject([:])

        storedDecisions = loadDecisions()
        subject.send(effectiveDecisions)

        featureFlagCancellable = featureFlagger.updatesPublisher
            .sink { [weak self] in
                guard let self else { return }
                subject.send(effectiveDecisions)
            }
    }

    func defaultDecision(for category: WebsitePermissionCategory) -> PersistedPermissionDecision {
        guard isFeatureEnabled else { return fallbackDecision }
        return storedDecisions[category] ?? fallbackDecision
    }

    func setDefaultDecision(_ decision: PersistedPermissionDecision, for category: WebsitePermissionCategory) {
        guard isFeatureEnabled,
              availableDecisions.contains(decision),
              storedDecisions[category] != decision
        else { return }

        storedDecisions[category] = decision
        storage.setDecisionRawValue(decision.rawValue, for: category)
        subject.send(effectiveDecisions)
    }

    // MARK: - Private

    private var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.websitePermissionsSettings)
    }

    private var effectiveDecisions: [WebsitePermissionCategory: PersistedPermissionDecision] {
        isFeatureEnabled ? storedDecisions : disabledDecisions
    }

    private var disabledDecisions: [WebsitePermissionCategory: PersistedPermissionDecision] {
        WebsitePermissionCategory.allCases.reduce(into: [:]) { $0[$1] = fallbackDecision }
    }

    private func loadDecisions() -> [WebsitePermissionCategory: PersistedPermissionDecision] {
        WebsitePermissionCategory.allCases.reduce(into: [:]) { decisions, category in
            let stored = storage.decisionRawValue(for: category)
                .flatMap(PersistedPermissionDecision.init(rawValue:))
                .flatMap { availableDecisions.contains($0) ? $0 : nil }
            decisions[category] = stored ?? fallbackDecision
        }
    }
}
