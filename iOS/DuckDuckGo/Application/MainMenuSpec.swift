//
//  MainMenuSpec.swift
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

import UIKit

enum MainMenuCommand: CaseIterable {
    case settings
}

struct MainMenuSpec {
    struct Shortcut: Equatable {
        let input: String
        let modifiers: UIKeyModifierFlags
    }

    struct Item {
        let command: MainMenuCommand
        let title: String
        let shortcut: Shortcut?
    }

    struct Menu {
        let identifier: UIMenu.Identifier
        let items: [Item]
    }

    let menus: [Menu]
    let removedMenus: [UIMenu.Identifier]
    let ownsKeyCommands: Bool

    init(isEnabled: Bool) {
        menus = [Menu(identifier: .preferences, items: [
            Item(command: .settings, title: UserText.settingsTitle,
                 shortcut: Shortcut(input: ",", modifiers: .command))
        ])]
        removedMenus = isEnabled ? [.format] : []
        ownsKeyCommands = isEnabled
    }

    func remainingKeyCommands(from commands: [UIKeyCommand]) -> [UIKeyCommand] {
        guard ownsKeyCommands else { return commands }
        let items = menus.flatMap(\.items)
        return commands.filter { command in
            !items.contains { item in
                item.command.action == command.action && item.shortcut?.input == command.input
                    && item.shortcut?.modifiers == command.modifierFlags
            }
        }
    }
}
