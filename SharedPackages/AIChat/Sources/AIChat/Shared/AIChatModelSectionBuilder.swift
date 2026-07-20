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

/// A section of AI models for display in a picker menu or dropdown.
public struct AIChatModelSection {
    public let header: String?
    public let items: [AIChatModel]

    public init(header: String?, items: [AIChatModel]) {
        self.header = header
        self.items = items
    }
}

/// Builds sectioned model lists for both the native menu and the NTP dropdown.
///
/// The section layout depends on subscription status:
/// - **Free user**: accessible models (no header), then "Advanced Models" section (disabled)
/// - **Subscribed user**: advanced models (no header), then "Basic Models" section
public enum AIChatModelSectionBuilder {

    /// Builds model sections from a list of models and subscription state.
    /// - Parameters:
    ///   - models: All available AI models with access already resolved.
    ///   - hasActiveSubscription: Whether the user has an active paid subscription.
    ///   - advancedSectionHeader: Localized header for the advanced/premium section (free users).
    ///   - basicSectionHeader: Localized header for the basic/free section (subscribed users).
    /// - Returns: An array of sections ready for display.
    public static func buildSections(
        models: [AIChatModel],
        hasActiveSubscription: Bool,
        advancedSectionHeader: String,
        basicSectionHeader: String
    ) -> [AIChatModelSection] {
        if hasActiveSubscription {
            return buildSubscribedSections(models: models, basicSectionHeader: basicSectionHeader)
        } else {
            return buildFreeSections(models: models, advancedSectionHeader: advancedSectionHeader)
        }
    }

    private static func buildFreeSections(models: [AIChatModel], advancedSectionHeader: String) -> [AIChatModelSection] {
        let accessible = models.filter { $0.entityHasAccess }
        let premium = models.filter { !$0.entityHasAccess }

        var sections = [AIChatModelSection]()
        if !accessible.isEmpty {
            sections.append(AIChatModelSection(header: nil, items: accessible))
        }
        if !premium.isEmpty {
            sections.append(AIChatModelSection(header: advancedSectionHeader, items: premium))
        }
        return sections
    }

    private static func buildSubscribedSections(models: [AIChatModel], basicSectionHeader: String) -> [AIChatModelSection] {
        // Only show models the user can actually access — hides models from higher tiers (e.g. pro-only for plus users)
        let accessible = models.filter { $0.entityHasAccess }
        let basic = accessible.filter { !$0.isAdvanced }
        let advanced = accessible.filter { $0.isAdvanced }

        var sections = [AIChatModelSection]()
        if !advanced.isEmpty {
            sections.append(AIChatModelSection(header: nil, items: advanced))
        }
        if !basic.isEmpty {
            sections.append(AIChatModelSection(header: basicSectionHeader, items: basic))
        }
        return sections
    }
}

/// A gated (subscriber-only) model paired with the public tier required to unlock it.
public struct AIChatGatedModel {
    public let model: AIChatModel
    public let requiredTier: AIChatModelPublicAccessTier
}

public extension AIChatModelSectionBuilder {
    /// Splits models into accessible and gated (each paired with its required tier), keeping gated
    /// models visible rather than hiding higher-tier ones like `buildSections` does.
    static func groupByAccess(models: [AIChatModel]) -> (accessible: [AIChatModel], gated: [AIChatGatedModel]) {
        let accessible = models.filter { $0.entityHasAccess }
        let gated = models.compactMap { model -> AIChatGatedModel? in
            guard !model.entityHasAccess, let requiredTier = model.lowestPublicAccessTier else { return nil }
            return AIChatGatedModel(model: model, requiredTier: requiredTier)
        }
        return (accessible, gated)
    }

    /// PoC ordering: per-tier "recommended" first, rest keep API order. Delete when backend ships ordering (task 1216559729471554).
    static func orderedAccessibleModels(_ models: [AIChatModel], userTier: AIChatUserTier) -> [AIChatModel] {
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
