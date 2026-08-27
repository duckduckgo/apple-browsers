//
//  DuckAiHighUsageModelNotice.swift
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

/// Models that spend the allowance far faster than the basic tier. Hand-maintained to mirror the web
/// app's `highUsageModelIds`; the models payload carries no equivalent field.
public enum DuckAiHighUsageModels {

    public static let ids: Set<String> = ["claude-opus-4-8"]

    public static func includes(_ modelId: String?) -> Bool {
        guard let modelId else { return false }
        return ids.contains(modelId)
    }
}

/// The informational notice for a high-usage model. Not a usage warning: it is keyed off the selected
/// model rather than the allowance, so it carries no percentage, no reset and no switch.
public struct DuckAiHighUsageModelNotice: Equatable {

    public let modelId: String
    /// Names the model in the copy, so the notice can't be built without one.
    public let modelShortName: String

    public init(modelId: String, modelShortName: String) {
        self.modelId = modelId
        self.modelShortName = modelShortName
    }
}

// MARK: - Dismissal

/// One-time per model, with no reset window to expire against — unlike the usage-limit dismissals.
public protocol DuckAiHighUsageNoticeDismissalStoring {
    func isDismissed(modelId: String) -> Bool
    func setDismissed(modelId: String)
}

public struct DuckAiHighUsageNoticeDismissalStore: DuckAiHighUsageNoticeDismissalStoring {

    private static let key = "aichat.high-usage-notice.dismissed-models"

    private let keyValueStore: ThrowingKeyValueStoring

    public init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public func isDismissed(modelId: String) -> Bool {
        dismissedModelIds().contains(modelId)
    }

    public func setDismissed(modelId: String) {
        var ids = dismissedModelIds()
        guard !ids.contains(modelId) else { return }
        ids.append(modelId)
        try? keyValueStore.set(ids, forKey: Self.key)
    }

    /// An unreadable record reads as "not dismissed": showing the notice again is the safe failure.
    private func dismissedModelIds() -> [String] {
        (try? keyValueStore.object(forKey: Self.key) as? [String]) ?? []
    }
}

/// For tests and any caller that wants dismissals to die with the session.
public final class InMemoryDuckAiHighUsageNoticeDismissalStore: DuckAiHighUsageNoticeDismissalStoring {

    private var dismissed: Set<String> = []

    public init() {}

    public func isDismissed(modelId: String) -> Bool { dismissed.contains(modelId) }
    public func setDismissed(modelId: String) { dismissed.insert(modelId) }
}

// MARK: - Resolver

/// Pure: every input is a parameter or an injected collaborator, so the rule set is testable without UI.
public struct DuckAiHighUsageModelNoticeResolver {

    /// Reported so each gate stays observable in the log.
    public enum NoNoticeReason: String {
        case noModelSelected
        case modelIsNotHighUsage
        case dismissed
        case modelHasNoName
    }

    public enum Outcome {
        case notice(DuckAiHighUsageModelNotice)
        case none(reason: NoNoticeReason)
    }

    private let dismissalStore: DuckAiHighUsageNoticeDismissalStoring

    public init(dismissalStore: DuckAiHighUsageNoticeDismissalStoring) {
        self.dismissalStore = dismissalStore
    }

    public func resolve(modelId: String?, modelShortName: String?) -> Outcome {
        guard let modelId else { return .none(reason: .noModelSelected) }
        guard DuckAiHighUsageModels.includes(modelId) else { return .none(reason: .modelIsNotHighUsage) }
        guard !dismissalStore.isDismissed(modelId: modelId) else { return .none(reason: .dismissed) }
        guard let modelShortName, !modelShortName.isEmpty else { return .none(reason: .modelHasNoName) }

        return .notice(DuckAiHighUsageModelNotice(modelId: modelId, modelShortName: modelShortName))
    }
}
