//
//  UnifiedToggleInputModelMenu.swift
//  DuckDuckGo
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

struct UnifiedToggleInputModelMenu: Equatable {

    struct Section: Equatable {
        let title: String
        let items: [Item]
    }

    struct Item: Equatable {
        let modelId: String
        let name: String
        let provider: AIChatModel.ModelProvider
        let isSelected: Bool
        let isDisabled: Bool
    }

    let sections: [Section]

    static func build(
        models: [AIChatModel],
        selectedId: String?,
        isBottomAnchored: Bool,
        hasActiveSubscription: Bool,
        advancedSectionTitle: String,
        basicSectionTitle: String
    ) -> UnifiedToggleInputModelMenu {
        var sections: [Section]

        if hasActiveSubscription {
            sections = buildSubscribedSections(
                models: models,
                selectedId: selectedId,
                advancedSectionTitle: advancedSectionTitle,
                basicSectionTitle: basicSectionTitle
            )
        } else {
            sections = buildFreeSections(
                models: models,
                selectedId: selectedId,
                advancedSectionTitle: advancedSectionTitle
            )
        }

        if isBottomAnchored {
            sections.reverse()
        }

        return UnifiedToggleInputModelMenu(sections: sections)
    }

    private static func buildFreeSections(
        models: [AIChatModel],
        selectedId: String?,
        advancedSectionTitle: String
    ) -> [Section] {
        let accessible = models.filter { $0.entityHasAccess }
        let premium = models.filter { !$0.entityHasAccess }

        let accessibleSection = Section(
            title: "",
            items: accessible.map { Item(model: $0, selectedId: selectedId, isDisabled: false) }
        )

        var sections = [accessibleSection]

        if !premium.isEmpty {
            let premiumSection = Section(
                title: advancedSectionTitle,
                items: premium.map { Item(model: $0, selectedId: selectedId, isDisabled: true) }
            )
            sections.append(premiumSection)
        }

        return sections
    }

    private static func buildSubscribedSections(
        models: [AIChatModel],
        selectedId: String?,
        advancedSectionTitle: String,
        basicSectionTitle: String
    ) -> [Section] {
        let advanced = models.filter { !$0.accessTier.contains("free") }
        let basic = models.filter { $0.accessTier.contains("free") }

        var sections = [Section]()

        if !advanced.isEmpty {
            sections.append(Section(
                title: advancedSectionTitle,
                items: advanced.map { Item(model: $0, selectedId: selectedId, isDisabled: !$0.entityHasAccess) }
            ))
        }

        if !basic.isEmpty {
            sections.append(Section(
                title: basicSectionTitle,
                items: basic.map { Item(model: $0, selectedId: selectedId, isDisabled: !$0.entityHasAccess) }
            ))
        }

        if sections.isEmpty {
            sections.append(Section(title: "", items: []))
        }

        return sections
    }
}

extension UnifiedToggleInputModelMenu.Item {
    init(model: AIChatModel, selectedId: String?, isDisabled: Bool) {
        self.modelId = model.id
        self.name = model.name
        self.provider = model.provider
        self.isSelected = model.id == selectedId
        self.isDisabled = isDisabled
    }
}
