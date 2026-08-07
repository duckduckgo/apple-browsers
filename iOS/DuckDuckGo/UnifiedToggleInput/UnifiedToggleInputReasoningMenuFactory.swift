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

    func makeMenu(
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
}
