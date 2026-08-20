//
//  DuckAiCheaperModelSuggester.swift
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

public struct DuckAiCheaperModelSuggestion: Equatable {

    public let modelId: String
    /// `nil` → the UI falls back to "Switch Model" instead of "Switch to {model}".
    public let modelShortName: String?

    public init(modelId: String, modelShortName: String?) {
        self.modelId = modelId
        self.modelShortName = modelShortName
    }
}

/// What the current chat needs a model to be able to do. All-empty means a plain text chat.
public struct DuckAiChatCapabilityRequirements: Equatable {

    public let needsImageUpload: Bool
    public let requiredFileTypes: [String]
    public let requiredTools: [AIChatRAGTool]

    public static let plainText = DuckAiChatCapabilityRequirements()

    public init(needsImageUpload: Bool = false,
                requiredFileTypes: [String] = [],
                requiredTools: [AIChatRAGTool] = []) {
        self.needsImageUpload = needsImageUpload
        self.requiredFileTypes = requiredFileTypes
        self.requiredTools = requiredTools
    }
}

/// Why no cheaper model was offered. Carried so the rule chain stays observable while there is no UI.
public enum DuckAiCheaperModelUnavailableReason: String {
    case recentlySteppedDown
    /// No model is selected, or its family has no known step-down ladder.
    case unknownCurrentModel
    /// Nothing cheaper in the same family that this user's tier can select.
    case noCheaperModelAvailable
    /// Cheaper siblings exist, but none cover the images / files / tools this chat needs.
    case cheaperModelMissingCapability
    /// The caller never asked — a reached message, or a surface with no CTA.
    case notApplicable
}

public enum DuckAiCheaperModelOutcome: Equatable {
    case suggestion(DuckAiCheaperModelSuggestion)
    case none(reason: DuckAiCheaperModelUnavailableReason)

    public var suggestion: DuckAiCheaperModelSuggestion? {
        guard case .suggestion(let suggestion) = self else { return nil }
        return suggestion
    }
}

public protocol DuckAiCheaperModelSuggesting {
    /// `.none` when no lower-cost model covers the tools / files / images the current chat needs.
    func suggestion() -> DuckAiCheaperModelOutcome
}

public struct NullDuckAiCheaperModelSuggester: DuckAiCheaperModelSuggesting {
    public init() {}
    public func suggestion() -> DuckAiCheaperModelOutcome { .none(reason: .notApplicable) }
}

/// The cheaper-model CTA: a one-click step down to the cheapest sibling in the same family that still
/// covers what the chat needs.
///
/// Two ladders, both ordered most to least expensive: Opus → Sonnet → Haiku, and GPT-5.4 → mini → nano.
/// Suggestions never cross families — stepping from Claude to GPT is a bigger change than a quota nudge
/// should make on the user's behalf.
///
/// Live state is read through closures rather than passed into `suggestion()`, so the protocol stays
/// zero-argument and callers don't have to thread chat state they have no other use for.
public struct DuckAiCheaperModelSuggester: DuckAiCheaperModelSuggesting {

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

    public func suggestion() -> DuckAiCheaperModelOutcome {
        guard !didRecentlyStepDown() else { return .none(reason: .recentlySteppedDown) }

        let models = modelsProvider()
        let currentModelId = currentModelIdProvider()
        guard let current = models.first(where: { $0.id == currentModelId }),
              let currentRung = Self.rung(for: current) else {
            return .none(reason: .unknownCurrentModel)
        }

        let cheaperSiblings: [(model: AIChatModel, cheapness: Int)] = models.compactMap { model in
            guard model.entityHasAccess, model.id != current.id,
                  let rung = Self.rung(for: model),
                  rung.family == currentRung.family,
                  rung.cheapness > currentRung.cheapness else { return nil }
            return (model, rung.cheapness)
        }
        guard !cheaperSiblings.isEmpty else { return .none(reason: .noCheaperModelAvailable) }

        // Cheapest that still fits, rather than one rung down: the point of the nudge is to buy back as
        // much quota as the chat can afford to give up.
        let requirements = requirementsProvider()
        guard let target = cheaperSiblings
            .filter({ Self.model($0.model, covers: requirements) })
            .max(by: { $0.cheapness < $1.cheapness })?
            .model else {
            return .none(reason: .cheaperModelMissingCapability)
        }

        return .suggestion(DuckAiCheaperModelSuggestion(
            modelId: target.id,
            modelShortName: target.shortName.isEmpty ? nil : target.shortName
        ))
    }

    private enum ModelFamily {
        case claude
        case gpt
    }

    /// `cheapness` orders rungs within a family — higher is cheaper, so a bigger number is a bigger saving.
    private struct Rung {
        let family: ModelFamily
        let cheapness: Int
    }

    // Model ids are inconsistent in the wild — "claude-opus-4-6" ships alongside "claude-sonnet-4.6" —
    // so families are matched on the lowercased display name, the same convention
    // `AIChatModelSectionBuilder.recommendedModelMatchers` already uses. Both go away together once the
    // backend ships ordering and `AIChatModelLabel.usesLimitsFaster` / `.everydayUse` can drive this.
    // https://app.asana.com/1/137249556945/task/1216559729471554
    private static func rung(for model: AIChatModel) -> Rung? {
        let name = model.name.lowercased()

        if name.contains("claude") {
            if name.contains("opus") { return Rung(family: .claude, cheapness: 0) }
            if name.contains("sonnet") { return Rung(family: .claude, cheapness: 1) }
            if name.contains("haiku") { return Rung(family: .claude, cheapness: 2) }
            return nil
        }

        // Order matters: "GPT-5.4 nano" contains "gpt" too, so the qualifiers have to be checked first.
        if name.contains("gpt") {
            if name.contains("nano") { return Rung(family: .gpt, cheapness: 2) }
            if name.contains("mini") { return Rung(family: .gpt, cheapness: 1) }
            return Rung(family: .gpt, cheapness: 0)
        }

        return nil
    }

    private static func model(_ model: AIChatModel, covers requirements: DuckAiChatCapabilityRequirements) -> Bool {
        guard !requirements.needsImageUpload || model.supportsImageUpload else { return false }

        let supportedFileTypes = Set(model.supportedFileTypes.map { $0.lowercased() })
        guard requirements.requiredFileTypes.allSatisfy({ supportedFileTypes.contains($0.lowercased()) }) else { return false }

        return requirements.requiredTools.allSatisfy(model.supportsTool)
    }
}
