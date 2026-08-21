//
//  DuckAiModelSuggester.swift
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
import os.log

public struct DuckAiModelSuggestion: Equatable {

    public let modelId: String
    /// `nil` → the UI falls back to "Switch Model" instead of "Switch to {model}".
    public let modelShortName: String?

    public init(modelId: String, modelShortName: String?) {
        self.modelId = modelId
        self.modelShortName = modelShortName
    }
}

public struct DuckAiChatCapabilityRequirements: Equatable {

    public let needsImageUpload: Bool
    /// MIME types, matching what `AIChatModel.supportedFileTypes` carries.
    public let requiredMimeTypes: [String]
    public let requiredTools: [AIChatRAGTool]

    public static let plainText = DuckAiChatCapabilityRequirements()

    public init(needsImageUpload: Bool = false,
                requiredMimeTypes: [String] = [],
                requiredTools: [AIChatRAGTool] = []) {
        self.needsImageUpload = needsImageUpload
        self.requiredMimeTypes = requiredMimeTypes
        self.requiredTools = requiredTools
    }
}

/// Carried so the rule chain stays observable in the log while there is no UI.
public enum DuckAiModelSuggestionUnavailableReason: String {
    case recentlySteppedDown
    case unknownCurrentModel
    case currentModelIsNotCostly
    case noEverydayUseModelAvailable
    case everydayUseModelMissingCapability
    case noFreeModelAvailable
    case freeModelMissingCapability
    case notApplicable
}

public enum DuckAiModelSuggestionOutcome: Equatable {
    case suggestion(DuckAiModelSuggestion)
    case none(reason: DuckAiModelSuggestionUnavailableReason)

    public var suggestion: DuckAiModelSuggestion? {
        guard case .suggestion(let suggestion) = self else { return nil }
        return suggestion
    }
}

public protocol DuckAiModelSuggesting {
    /// A lower-cost model to head off an approaching limit.
    func cheaperModel() -> DuckAiModelSuggestionOutcome
    /// A free-tier model to fall back to once an advanced-model allowance is spent.
    func freeModel() -> DuckAiModelSuggestionOutcome
}

public struct NullDuckAiModelSuggester: DuckAiModelSuggesting {
    public init() {}
    public func cheaperModel() -> DuckAiModelSuggestionOutcome { .none(reason: .notApplicable) }
    public func freeModel() -> DuckAiModelSuggestionOutcome { .none(reason: .notApplicable) }
}

/// Driven by `AIChatModelLabel` rather than a hardcoded ladder: a name-matched ladder got it actively
/// wrong, stepping `gpt-5.4` down to `gpt-5.4-mini`, which is itself `usesLimitsFaster`.
public struct DuckAiModelSuggester: DuckAiModelSuggesting {

    private let modelsProvider: () -> [AIChatModel]
    private let currentModelIdProvider: () -> String?
    private let requirementsProvider: () -> DuckAiChatCapabilityRequirements
    private let didRecentlyStepDown: () -> Bool

    public init(modelsProvider: @escaping () -> [AIChatModel],
                currentModelIdProvider: @escaping () -> String?,
                requirementsProvider: @escaping () -> DuckAiChatCapabilityRequirements = { .plainText },
                didRecentlyStepDown: @escaping () -> Bool = { false }) {
        self.modelsProvider = modelsProvider
        self.currentModelIdProvider = currentModelIdProvider
        self.requirementsProvider = requirementsProvider
        self.didRecentlyStepDown = didRecentlyStepDown
    }

    public func cheaperModel() -> DuckAiModelSuggestionOutcome {
        let models = modelsProvider()
        let current = models.first { $0.id == currentModelIdProvider() }
        let outcome = resolveCheaper(current: current, in: models)

        // Labels are believed to be per-tier; the anonymous payload only shows the free-tier split, so
        // logging the current one is how that gets confirmed against a real account.
        Logger.aiChat.debug("""
            Duck.ai cheaper model: current=\(current?.id ?? "none", privacy: .public) \
            label=\(current?.label?.rawValue ?? "none", privacy: .public) \
            outcome=\(Self.describe(outcome), privacy: .public)
            """)
        return outcome
    }

    /// `isAdvanced` is `!accessTier.contains("free")`, so a non-advanced model is one the free tier gets.
    public func freeModel() -> DuckAiModelSuggestionOutcome {
        let models = modelsProvider()
        let current = models.first { $0.id == currentModelIdProvider() }
        let candidates = models.filter { $0.entityHasAccess && $0.id != current?.id && !$0.isAdvanced }
        guard !candidates.isEmpty else { return .none(reason: .noFreeModelAvailable) }

        let capable = candidates.filter { Self.model($0, covers: requirementsProvider()) }
        guard let target = capable.first else { return .none(reason: .freeModelMissingCapability) }

        return .suggestion(DuckAiModelSuggestion(
            modelId: target.id,
            modelShortName: target.shortName.isEmpty ? nil : target.shortName
        ))
    }

    private func resolveCheaper(current: AIChatModel?, in models: [AIChatModel]) -> DuckAiModelSuggestionOutcome {
        guard !didRecentlyStepDown() else { return .none(reason: .recentlySteppedDown) }
        guard let current else { return .none(reason: .unknownCurrentModel) }

        // An unlabelled model is not known to be costly, and nudging off it could raise usage.
        guard current.label == .usesLimitsFaster else { return .none(reason: .currentModelIsNotCostly) }

        let candidates = models.filter { $0.entityHasAccess && $0.id != current.id && $0.label == .everydayUse }
        guard !candidates.isEmpty else { return .none(reason: .noEverydayUseModelAvailable) }

        let capable = candidates.filter { Self.model($0, covers: requirementsProvider()) }
        guard !capable.isEmpty else { return .none(reason: .everydayUseModelMissingCapability) }

        // Staying with the same provider makes for a smaller change than crossing to another.
        let target = capable.first { $0.provider == current.provider } ?? capable[0]

        return .suggestion(DuckAiModelSuggestion(
            modelId: target.id,
            modelShortName: target.shortName.isEmpty ? nil : target.shortName
        ))
    }

    private static func describe(_ outcome: DuckAiModelSuggestionOutcome) -> String {
        switch outcome {
        case .suggestion(let suggestion): return "switch-to:\(suggestion.modelId)"
        case .none(let reason): return reason.rawValue
        }
    }

    private static func model(_ model: AIChatModel, covers requirements: DuckAiChatCapabilityRequirements) -> Bool {
        guard !requirements.needsImageUpload || model.supportsImageUpload else { return false }

        let supported = Set(model.supportedFileTypes.map { $0.lowercased() })
        guard requirements.requiredMimeTypes.allSatisfy({ supported.contains($0.lowercased()) }) else { return false }

        return requirements.requiredTools.allSatisfy(model.supportsTool)
    }
}
