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
        let basic = accessible.filter { $0.accessTier.contains(AIChatUserTier.free.rawValue) }
        let advanced = accessible.filter { !$0.accessTier.contains(AIChatUserTier.free.rawValue) }

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
