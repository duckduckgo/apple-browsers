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
import DesignResourcesKitIcons
import UIKit

enum UnifiedToggleInputGatedSectionTitleResolver {
    static func title(for userTier: AIChatUserTier, freeTrialEligibility: FreeTrialEligibility) -> String {
        if userTier == .plus {
            return UserText.aiChatModelPickerProPlanExclusive
        }
        if freeTrialEligibility == .ineligible {
            return UserText.aiChatModelPickerSubscriberExclusive
        }
        return UserText.aiChatModelPickerTryFree
    }
}

struct UnifiedToggleInputModelMenuFactory {

    private let isUpdatedModelPickerEnabled: Bool

    init(isUpdatedModelPickerEnabled: Bool) {
        self.isUpdatedModelPickerEnabled = isUpdatedModelPickerEnabled
    }

    func makeMenu(
        models: [AIChatModel],
        selectedId: String?,
        userTier: AIChatUserTier,
        freeTrialEligibility: FreeTrialEligibility = .unknown,
        onSelect: @escaping (String) -> Void
    ) -> UIMenu {
        if isUpdatedModelPickerEnabled {
            return makeUpdatedMenu(
                models: models,
                selectedId: selectedId,
                userTier: userTier,
                freeTrialEligibility: freeTrialEligibility,
                onSelect: onSelect)
        }

        return makeLegacyMenu(models: models, selectedId: selectedId, onSelect: onSelect)
    }

    func selectedShortName(models: [AIChatModel], selectedId: String?) -> String? {
        models.first(where: { $0.id == selectedId })?.shortName
    }

    // MARK: - Private

    private func makeLegacyMenu(
        models: [AIChatModel],
        selectedId: String?,
        onSelect: @escaping (String) -> Void
    ) -> UIMenu {
        let description = UnifiedToggleInputModelMenu.build(
            models: models,
            selectedId: selectedId,
            plusSectionTitle: UserText.aiChatPlusModelsSectionHeader,
            proSectionTitle: UserText.aiChatProModelsSectionHeader
        )

        let modelLookup = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        let sections = description.sections.map { section in
            let actions = section.items.map { item -> UIAction in
                let model = modelLookup[item.modelId]
                return UIAction(
                    title: item.name,
                    image: model?.menuIcon,
                    attributes: [],
                    state: item.isSelected ? .on : .off
                ) { _ in
                    onSelect(item.modelId)
                }
            }

            return UIMenu(title: section.title, options: [.displayInline, .singleSelection], children: actions)
        }

        return UIMenu(children: sections)
    }

    private func makeUpdatedMenu(
        models: [AIChatModel],
        selectedId: String?,
        userTier: AIChatUserTier,
        freeTrialEligibility: FreeTrialEligibility,
        onSelect: @escaping (String) -> Void
    ) -> UIMenu {
        let groupedModels = AIChatModelSectionBuilder.groupByAccess(models: models)
        let groupedAvailableModels = AIChatModelSectionBuilder.groupByEditorialLabel(models: groupedModels.accessible)
        let availableModels = groupedAvailableModels.withLabel + groupedAvailableModels.withoutLabel
        var children: [UIMenuElement] = availableModels.map { model in
            makeUpdatedAction(
                model: model,
                selectedId: selectedId,
                isGated: false,
                onSelect: onSelect
            )
        }

        if !groupedModels.gated.isEmpty {
            let gatedActions = groupedModels.gated.map { gatedModel in
                makeUpdatedAction(
                    model: gatedModel.model,
                    selectedId: selectedId,
                    isGated: true,
                    onSelect: onSelect
                )
            }
            let gatedSectionTitle = UnifiedToggleInputGatedSectionTitleResolver.title(
                for: userTier,
                freeTrialEligibility: freeTrialEligibility)
            children.append(UIMenu(title: gatedSectionTitle, options: .displayInline, children: gatedActions))
        }

        return UIMenu(options: .singleSelection, children: children)
    }

    private func makeUpdatedAction(
        model: AIChatModel,
        selectedId: String?,
        isGated: Bool,
        onSelect: @escaping (String) -> Void
    ) -> UIAction {
        UIAction(
            title: isGated ? "\(model.name)…" : model.name,
            subtitle: isGated ? nil : model.label?.localizedText,
            image: model.updatedModelPickerMenuIcon,
            state: !isGated && model.id == selectedId ? .on : .off
        ) { _ in
            onSelect(model.id)
        }
    }
}

private extension AIChatModel {
    var updatedModelPickerMenuIcon: UIImage? {
        switch provider {
        case .unknown:
            return DesignSystemImages.Glyphs.Size16.aiModelOSS
        default:
            return menuIcon
        }
    }
}
