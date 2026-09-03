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

/// Carried so the rule chain stays observable in the log.
public enum DuckAiModelSuggestionUnavailableReason: String {
    /// Web offered nothing for the model this picker is on — it is already the cheapest.
    case noTargetForSelectedModel
    /// Not in the native model list, or the entity can't access them.
    case targetModelUnavailable
    /// Can't handle what is already in the draft (an image, a file type, a tool).
    case targetModelMissingCapability
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
    /// Resolves the model a switch CTA should offer, or why it can't offer one.
    func resolve(_ cta: DuckAiUsageCta) -> DuckAiModelSuggestionOutcome
}

public struct NullDuckAiModelSuggester: DuckAiModelSuggesting {
    public init() {}
    public func resolve(_ cta: DuckAiUsageCta) -> DuckAiModelSuggestionOutcome { .none(reason: .notApplicable) }
}

/// No ladder of its own: an earlier name-matched one stepped `gpt-5.4` down to `gpt-5.4-mini`, which
/// is itself a fast-limit model. Web can't see this surface's draft, and only native knows its picker.
public struct DuckAiModelSuggester: DuckAiModelSuggesting {

    private let modelsProvider: () -> [AIChatModel]
    private let currentModelIdProvider: () -> String?
    private let requirementsProvider: () -> DuckAiChatCapabilityRequirements

    public init(modelsProvider: @escaping () -> [AIChatModel],
                currentModelIdProvider: @escaping () -> String?,
                requirementsProvider: @escaping () -> DuckAiChatCapabilityRequirements = { .plainText }) {
        self.modelsProvider = modelsProvider
        self.currentModelIdProvider = currentModelIdProvider
        self.requirementsProvider = requirementsProvider
    }

    public func resolve(_ cta: DuckAiUsageCta) -> DuckAiModelSuggestionOutcome {
        let currentModelId = currentModelIdProvider()
        let outcome = resolve(cta, currentModelId: currentModelId)

        Logger.aiChat.debug("""
            Duck.ai usage CTA target: cta=\(cta.id.rawValue, privacy: .public) \
            picker=\(currentModelId ?? "none", privacy: .public) \
            outcome=\(Self.describe(outcome), privacy: .public)
            """)
        return outcome
    }

    private func resolve(_ cta: DuckAiUsageCta, currentModelId: String?) -> DuckAiModelSuggestionOutcome {
        let target = cta.target(forSelectedModelId: currentModelId)
        guard !target.isEmpty else { return .none(reason: .noTargetForSelectedModel) }

        let models = modelsProvider()
        // The top-level target is keyed to web's model, not ours, so it can name the one we are on.
        let available = target.candidateModelIds
            .filter { $0 != currentModelId }
            .compactMap { id in models.first { $0.id == id && $0.entityHasAccess } }
        guard !available.isEmpty else { return .none(reason: .targetModelUnavailable) }

        let requirements = requirementsProvider()
        guard let model = available.first(where: { Self.model($0, covers: requirements) }) else {
            return .none(reason: .targetModelMissingCapability)
        }

        return .suggestion(DuckAiModelSuggestion(
            modelId: model.id,
            modelShortName: model.shortName.isEmpty ? nil : model.shortName
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
