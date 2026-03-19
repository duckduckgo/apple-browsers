//
//  DuckAIChromeButtonsVisibilityManager.swift
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

import Foundation

enum DuckAIChromeButtonType {
    case duckAI
    case sidebar
}

protocol DuckAIChromeButtonsVisibilityManaging {
    func isHidden(_ button: DuckAIChromeButtonType) -> Bool
    func toggleVisibility(for button: DuckAIChromeButtonType)
    func setHidden(_ hidden: Bool, for button: DuckAIChromeButtonType)
}

final class LocalDuckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging {

    private var persistor: DuckAIChromeButtonsUserDefaultsPersistor

    init(persistor: DuckAIChromeButtonsUserDefaultsPersistor = DuckAIChromeButtonsUserDefaultsPersistor()) {
        self.persistor = persistor
    }

    func isHidden(_ button: DuckAIChromeButtonType) -> Bool {
        switch button {
        case .duckAI:
            persistor.isDuckAIButtonHidden
        case .sidebar:
            persistor.isSidebarButtonHidden
        }
    }

    func toggleVisibility(for button: DuckAIChromeButtonType) {
        setHidden(!isHidden(button), for: button)
    }

    func setHidden(_ hidden: Bool, for button: DuckAIChromeButtonType) {
        let currentValue = isHidden(button)
        guard currentValue != hidden else { return }

        switch button {
        case .duckAI:
            persistor.isDuckAIButtonHidden = hidden
        case .sidebar:
            persistor.isSidebarButtonHidden = hidden
        }

        NotificationCenter.default.post(name: .duckAIChromeButtonsVisibilityChanged, object: nil)
    }
}

extension NSNotification.Name {
    static let duckAIChromeButtonsVisibilityChanged = NSNotification.Name("duck-ai-chrome.buttons-visibility-changed")
}
