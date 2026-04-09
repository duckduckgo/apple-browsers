//
//  UnifiedToggleInputModelMenuFactory.swift
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
import UIKit

struct UnifiedToggleInputModelMenuFactory {

    func makeMenu(
        models: [AIChatModel],
        selectedId: String?,
        isBottomAnchored: Bool,
        hasActiveSubscription: Bool,
        advancedSectionTitle: String,
        basicSectionTitle: String,
        onSelect: @escaping (String) -> Void
    ) -> UIMenu {
        let description = UnifiedToggleInputModelMenu.build(
            models: models,
            selectedId: selectedId,
            isBottomAnchored: isBottomAnchored,
            hasActiveSubscription: hasActiveSubscription,
            advancedSectionTitle: advancedSectionTitle,
            basicSectionTitle: basicSectionTitle
        )

        let modelLookup = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let sections = description.sections.map { section in
            let actions = section.items.map { item -> UIAction in
                let model = modelLookup[item.modelId]
                return UIAction(
                    title: item.name,
                    image: model?.menuIcon,
                    attributes: item.isDisabled ? .disabled : [],
                    state: item.isSelected ? .on : .off
                ) { _ in
                    onSelect(item.modelId)
                }
            }

            var options: UIMenu.Options = .displayInline
            if !section.items.contains(where: { $0.isDisabled }) {
                options.insert(.singleSelection)
            }

            return UIMenu(title: section.title, options: options, children: actions)
        }

        return UIMenu(children: sections)
    }

    func selectedShortName(models: [AIChatModel], selectedId: String?) -> String? {
        models.first(where: { $0.id == selectedId })?.shortName
    }
}
