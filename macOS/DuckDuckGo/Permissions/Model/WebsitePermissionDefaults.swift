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
    /// The options this category's "Default" radio group offers, in the order the design lists them.
    func availableDecisions(for category: WebsitePermissionCategory) -> [PersistedPermissionDecision]
    var fallbackDecision: PersistedPermissionDecision { get }
    var defaultsPublisher: AnyPublisher<[WebsitePermissionCategory: PersistedPermissionDecision], Never> { get }
    func defaultDecision(for category: WebsitePermissionCategory) -> PersistedPermissionDecision
    func setDefaultDecision(_ decision: PersistedPermissionDecision, for category: WebsitePermissionCategory)
}

final class WebsitePermissionDefaults: WebsitePermissionDefaultsProtocol {

    let fallbackDecision: PersistedPermissionDecision = .ask

    private let storage: WebsitePermissionDefaultsStorage
    private let featureFlagger: FeatureFlagger
    private let autoplayPreferences: AutoplayPreferences
    /// Holds every category but Autoplay, whose default lives in `AutoplayPreferences`.
    private var storedDecisions: [WebsitePermissionCategory: PersistedPermissionDecision]
    private let subject: CurrentValueSubject<[WebsitePermissionCategory: PersistedPermissionDecision], Never>
    private var cancellables = Set<AnyCancellable>()

    var defaultsPublisher: AnyPublisher<[WebsitePermissionCategory: PersistedPermissionDecision], Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init(storage: WebsitePermissionDefaultsStorage,
         featureFlagger: FeatureFlagger,
         autoplayPreferences: AutoplayPreferences) {
        self.storage = storage
        self.featureFlagger = featureFlagger
        self.autoplayPreferences = autoplayPreferences

        self.storedDecisions = [:]
        self.subject = CurrentValueSubject([:])

        storedDecisions = loadDecisions()
        subject.send(effectiveDecisions)

        featureFlagger.updatesPublisher
            .sink { [weak self] in
                guard let self else { return }
                subject.send(effectiveDecisions)
            }
            .store(in: &cancellables)

        // The all-sites autoplay mode is also editable from the Permission Center, so the pane has to
        // follow changes made outside it. `@Published` fires on willSet, so the new value is passed
        // through rather than read back off `autoplayPreferences`.
        autoplayPreferences.$autoplayBlockingMode
            .dropFirst()
            .sink { [weak self] blockingMode in
                guard let self else { return }
                subject.send(effectiveDecisions(autoplayBlockingMode: blockingMode))
            }
            .store(in: &cancellables)
    }

    /// Autoplay chooses which media may start on its own rather than whether to grant access, so it
    /// offers all three of its states. Every other category keeps the uniform pair, with deliberately
    /// no blanket grant: that would hand out camera, microphone or location without a prompt.
    func availableDecisions(for category: WebsitePermissionCategory) -> [PersistedPermissionDecision] {
        category == .autoplay ? PermissionType.autoplayPolicy.editableDecisions : Self.uniformDecisions
    }

    func defaultDecision(for category: WebsitePermissionCategory) -> PersistedPermissionDecision {
        guard isFeatureEnabled else { return fallbackDecision }
        guard category != .autoplay else { return PersistedPermissionDecision(autoplayPreferences.autoplayBlockingMode) }
        return storedDecisions[category] ?? fallbackDecision
    }

    func setDefaultDecision(_ decision: PersistedPermissionDecision, for category: WebsitePermissionCategory) {
        guard isFeatureEnabled, availableDecisions(for: category).contains(decision) else { return }

        // Autoplay writes through to the all-sites blocking mode, which also fires its own pixel and
        // feeds the WebKit policy; `autoplayPreferences` publishes the change back to `subject`.
        guard category != .autoplay else {
            autoplayPreferences.autoplayBlockingMode = decision.autoplayBlockingMode
            return
        }

        guard storedDecisions[category] != decision else { return }

        storedDecisions[category] = decision
        storage.setDecisionRawValue(decision.rawValue, for: category)
        subject.send(effectiveDecisions)
    }

    // MARK: - Private

    private var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.websitePermissionsSettings)
    }

    private static let uniformDecisions: [PersistedPermissionDecision] = [.ask, .deny]

    private var effectiveDecisions: [WebsitePermissionCategory: PersistedPermissionDecision] {
        effectiveDecisions(autoplayBlockingMode: autoplayPreferences.autoplayBlockingMode)
    }

    private func effectiveDecisions(
        autoplayBlockingMode: AutoplayBlockingMode
    ) -> [WebsitePermissionCategory: PersistedPermissionDecision] {
        guard isFeatureEnabled else { return disabledDecisions }
        var decisions = storedDecisions
        decisions[.autoplay] = PersistedPermissionDecision(autoplayBlockingMode)
        return decisions
    }

    private var disabledDecisions: [WebsitePermissionCategory: PersistedPermissionDecision] {
        WebsitePermissionCategory.allCases.reduce(into: [:]) { $0[$1] = fallbackDecision }
    }

    /// Autoplay is skipped: its default is the all-sites blocking mode, not a value of our own.
    private func loadDecisions() -> [WebsitePermissionCategory: PersistedPermissionDecision] {
        WebsitePermissionCategory.allCases.filter { $0 != .autoplay }.reduce(into: [:]) { decisions, category in
            let stored = storage.decisionRawValue(for: category)
                .flatMap(PersistedPermissionDecision.init(rawValue:))
                .flatMap { Self.uniformDecisions.contains($0) ? $0 : nil }
            decisions[category] = stored ?? fallbackDecision
        }
    }
}
