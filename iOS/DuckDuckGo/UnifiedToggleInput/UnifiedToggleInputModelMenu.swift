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
        selectedId: String,
        isBottomAnchored: Bool,
        advancedSectionTitle: String
    ) -> UnifiedToggleInputModelMenu {
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

        if isBottomAnchored {
            sections.reverse()
        }

        return UnifiedToggleInputModelMenu(sections: sections)
    }
}

extension UnifiedToggleInputModelMenu.Item {
    init(model: AIChatModel, selectedId: String, isDisabled: Bool) {
        self.modelId = model.id
        self.name = model.name
        self.provider = model.provider
        self.isSelected = model.id == selectedId
        self.isDisabled = isDisabled
    }
}
