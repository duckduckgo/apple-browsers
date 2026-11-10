//
//  LocalSummariesPromo.swift
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

import AIChat
import Combine
import Foundation
import NewTabPage
import Persistence

extension Notification.Name {
    static let localSummariesPromoOutcomeDidChange = Notification.Name("localSummariesPromoOutcomeDidChange")
}

enum LocalSummariesPromoOutcome: String {
    case tried
    case closed
}

enum LocalSummariesPromoEligibility {

    static func isEligible(isFeatureOn: Bool,
                           availability: AIChatLocalModelAvailability,
                           isOptedIn: Bool,
                           outcome: LocalSummariesPromoOutcome?) -> Bool {
        isFeatureOn && availability.isAvailable && !isOptedIn && outcome == nil
    }
}

/// Offers local page summaries with Apple Intelligence in the band under the Duck.ai address-bar panel.
@MainActor
final class LocalSummariesPromo {

    private static let outcomeKey = "duckai.local-summaries-promo.outcome"

    private let localModelService: AIChatLocalModelService
    private let keyValueStore: ThrowingKeyValueStoring
    private let notificationCenter: NotificationCenter

    init(localModelService: AIChatLocalModelService,
         keyValueStore: ThrowingKeyValueStoring,
         notificationCenter: NotificationCenter = .default) {
        self.localModelService = localModelService
        self.keyValueStore = keyValueStore
        self.notificationCenter = notificationCenter
    }

    var isEligible: Bool {
        LocalSummariesPromoEligibility.isEligible(isFeatureOn: localModelService.isFeatureEnabled,
                                                  availability: localModelService.availability,
                                                  isOptedIn: localModelService.isOptedIn,
                                                  outcome: outcome)
    }

    var outcome: LocalSummariesPromoOutcome? {
        Self.storedOutcome(in: keyValueStore)
    }

    static func storedOutcome(in keyValueStore: ThrowingKeyValueStoring) -> LocalSummariesPromoOutcome? {
        ((try? keyValueStore.object(forKey: outcomeKey)) as? String).flatMap(LocalSummariesPromoOutcome.init(rawValue:))
    }

    /// Reuses the launcher promo's shape: the bold `message` is the "New" badge and the rest is the offer.
    func presentation() -> NewTabPageDataModel.OmnibarLauncherPromo? {
        guard isEligible else { return nil }
        return .init(message: UserText.newBadge,
                     secondaryText: " • " + UserText.localSummariesPromoMessage,
                     ctaLabel: UserText.localSummariesPromoTry,
                     dismissible: true)
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        Publishers.Merge(
            localModelService.changesPublisher,
            notificationCenter.publisher(for: .localSummariesPromoOutcomeDidChange).map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .compactMap { [weak self] in self.map { $0.presentation() } }
        .removeDuplicates()
        .dropFirst()
        .map { _ in () }
        .eraseToAnyPublisher()
    }

    func tryNow() {
        localModelService.optIn()
        record(.tried)
    }

    func dismiss() {
        record(.closed)
    }

    private func record(_ outcome: LocalSummariesPromoOutcome) {
        try? keyValueStore.set(outcome.rawValue, forKey: Self.outcomeKey)
        notificationCenter.post(name: .localSummariesPromoOutcomeDidChange, object: nil)
    }

    static func resetOutcome(in keyValueStore: ThrowingKeyValueStoring, notificationCenter: NotificationCenter = .default) {
        try? keyValueStore.removeObject(forKey: outcomeKey)
        notificationCenter.post(name: .localSummariesPromoOutcomeDidChange, object: nil)
    }
}
