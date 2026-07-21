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
        let accessTier: AIChatModelPublicAccessTier
    }

    let sections: [Section]

    static func build(
        models: [AIChatModel],
        selectedId: String?,
        plusSectionTitle: String,
        proSectionTitle: String
    ) -> UnifiedToggleInputModelMenu {
        let sections = buildTierSections(
            models: models,
            selectedId: selectedId,
            plusSectionTitle: plusSectionTitle,
            proSectionTitle: proSectionTitle
        )

        return UnifiedToggleInputModelMenu(sections: sections)
    }

    private static func buildTierSections(
        models: [AIChatModel],
        selectedId: String?,
        plusSectionTitle: String,
        proSectionTitle: String
    ) -> [Section] {
        let groupedModels = models.reduce(into: [AIChatModelPublicAccessTier: [AIChatModel]]()) { groups, model in
            guard let tier = model.lowestPublicAccessTier else { return }
            groups[tier, default: []].append(model)
        }

        var sections = [Section]()
        if let freeModels = groupedModels[.free], !freeModels.isEmpty {
            sections.append(Section(
                title: "",
                items: freeModels.map { Item(model: $0, selectedId: selectedId, accessTier: .free) }
            ))
        }

        if let plusModels = groupedModels[.plus], !plusModels.isEmpty {
            sections.append(Section(
                title: plusSectionTitle,
                items: plusModels.map { Item(model: $0, selectedId: selectedId, accessTier: .plus) }
            ))
        }

        if let proModels = groupedModels[.pro], !proModels.isEmpty {
            sections.append(Section(
                title: proSectionTitle,
                items: proModels.map { Item(model: $0, selectedId: selectedId, accessTier: .pro) }
            ))
        }

        return sections
    }
}

extension UnifiedToggleInputModelMenu.Item {
    init(model: AIChatModel, selectedId: String?, accessTier: AIChatModelPublicAccessTier) {
        self.modelId = model.id
        self.name = model.name
        self.provider = model.provider
        self.isSelected = model.id == selectedId
        self.accessTier = accessTier
    }
}
