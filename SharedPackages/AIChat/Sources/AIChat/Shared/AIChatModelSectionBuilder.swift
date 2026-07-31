//
//  AIChatModelSectionBuilder.swift
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

/// A gated (subscriber-only) model paired with the public tier required to unlock it.
public struct AIChatGatedModel {
    public let model: AIChatModel
    public let requiredTier: AIChatModelPublicAccessTier
}

/// Splits and orders AI models for display in a picker menu or dropdown, shared by the native
/// address bar's model picker and the NTP dropdown.
public enum AIChatModelSectionBuilder {

    /// Splits models into accessible and gated (each paired with its required tier) — gated models
    /// stay visible, with an upsell, rather than being hidden from a subscriber whose tier doesn't yet cover them.
    public static func groupByAccess(models: [AIChatModel]) -> (accessible: [AIChatModel], gated: [AIChatGatedModel]) {
        let accessible = models.filter { $0.entityHasAccess }
        let gated = models.compactMap { model -> AIChatGatedModel? in
            guard !model.entityHasAccess, let requiredTier = model.lowestPublicAccessTier else { return nil }
            return AIChatGatedModel(model: model, requiredTier: requiredTier)
        }
        return (accessible, gated)
    }

    /// PoC ordering: per-tier "recommended" first, rest keep API order. Delete when backend ships ordering (task 1216559729471554).
    public static func orderedAccessibleModels(_ models: [AIChatModel], userTier: AIChatUserTier) -> [AIChatModel] {
        var remaining = models
        var recommended: [AIChatModel] = []
        for matches in recommendedModelMatchers(for: userTier) {
            guard let index = remaining.firstIndex(where: { matches($0.name.lowercased()) }) else { continue }
            recommended.append(remaining.remove(at: index))
        }
        return recommended + remaining
    }

    /// Per-tier "recommended" matchers in display order, matched by lowercased name substring (family, not id).
    private static func recommendedModelMatchers(for userTier: AIChatUserTier) -> [(String) -> Bool] {
        let isFullGPT: (String) -> Bool = { $0.contains("gpt") && !$0.contains("mini") && !$0.contains("nano") }
        switch userTier {
        case .free:
            return [
                { $0.contains("nano") },
                { $0.contains("mini") },
                { $0.contains("claude") && $0.contains("haiku") }
            ]
        case .plus, .internal:
            return [
                isFullGPT,
                { $0.contains("claude") && $0.contains("sonnet") }
            ]
        case .pro:
            return [
                isFullGPT,
                { $0.contains("claude") && $0.contains("opus") }
            ]
        }
    }
}
