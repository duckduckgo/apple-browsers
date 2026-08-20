//
//  UnifiedToggleInputReasoningMenuFactory.swift
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

/// Builds the reasoning-mode pull-down menu
struct UnifiedToggleInputReasoningMenuFactory {

    private let isUpdatedModelPickerEnabled: Bool

    init(isUpdatedModelPickerEnabled: Bool) {
        self.isUpdatedModelPickerEnabled = isUpdatedModelPickerEnabled
    }

    func makeMenu(
        model: AIChatModel,
        selectedMode: AIChatReasoningMode?,
        userTier: AIChatUserTier,
        freeTrialEligibility: FreeTrialEligibility = .unknown,
        onSelect: @escaping (AIChatReasoningMode) -> Void
    ) -> UIMenu? {
        if isUpdatedModelPickerEnabled {
            return makeUpdatedMenu(
                model: model,
                selectedMode: selectedMode,
                userTier: userTier,
                freeTrialEligibility: freeTrialEligibility,
                onSelect: onSelect)
        }

        return makeLegacyMenu(model: model, selectedMode: selectedMode, onSelect: onSelect)
    }

    private func makeLegacyMenu(
        model: AIChatModel,
        selectedMode: AIChatReasoningMode?,
        onSelect: @escaping (AIChatReasoningMode) -> Void
    ) -> UIMenu? {
        guard model.supportsReasoningPicker else { return nil }

        let actions = model.availableReasoningModes.map { mode in
            UIAction(
                title: mode.unifiedToggleInputTitle,
                subtitle: mode.unifiedToggleInputSubtitle,
                image: mode.unifiedToggleInputMenuImage,
                state: mode == selectedMode ? .on : .off
            ) { _ in
                onSelect(mode)
            }
        }

        return UIMenu(options: .singleSelection, children: actions)
    }

    private func makeUpdatedMenu(
        model: AIChatModel,
        selectedMode: AIChatReasoningMode?,
        userTier: AIChatUserTier,
        freeTrialEligibility: FreeTrialEligibility,
        onSelect: @escaping (AIChatReasoningMode) -> Void
    ) -> UIMenu? {
        guard model.supportsReasoningPicker else { return nil }

        let accessibleModes = model.availableReasoningModes.filter { model.accessibleReasoningModes.contains($0) }
        let gatedModes = model.availableReasoningModes.filter { !model.accessibleReasoningModes.contains($0) }
        var children: [UIMenuElement] = accessibleModes.map { mode in
            makeUpdatedAction(mode: mode, selectedMode: selectedMode, isGated: false, onSelect: onSelect)
        }

        if !gatedModes.isEmpty {
            let gatedActions = gatedModes.map { mode in
                makeUpdatedAction(mode: mode, selectedMode: selectedMode, isGated: true, onSelect: onSelect)
            }
            let gatedSectionTitle = UnifiedToggleInputGatedSectionTitleResolver.title(
                for: userTier,
                freeTrialEligibility: freeTrialEligibility)
            children.append(UIMenu(title: gatedSectionTitle, options: .displayInline, children: gatedActions))
        }

        return UIMenu(options: .singleSelection, children: children)
    }

    private func makeUpdatedAction(
        mode: AIChatReasoningMode,
        selectedMode: AIChatReasoningMode?,
        isGated: Bool,
        onSelect: @escaping (AIChatReasoningMode) -> Void
    ) -> UIAction {
        UIAction(
            title: isGated ? "\(mode.unifiedToggleInputTitle)…" : mode.unifiedToggleInputTitle,
            subtitle: mode.unifiedToggleInputSubtitle,
            image: mode.unifiedToggleInputMenuImage,
            state: !isGated && mode == selectedMode ? .on : .off
        ) { _ in
            onSelect(mode)
        }
    }
}
