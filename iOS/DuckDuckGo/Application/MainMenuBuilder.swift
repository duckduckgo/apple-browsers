//
//  MainMenuBuilder.swift
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

struct MainMenuBuilder {
    func keyCommands(for spec: MainMenuSpec, from commands: [UIKeyCommand],
                     availability: MenuCommandAvailability) -> [UIKeyCommand] {
        let remainingCommands = spec.remainingKeyCommands(from: commands)
        guard spec.shortcutRegistration != .menu else { return remainingCommands }
        let shortcuts = spec.shortcutItems
            .filter { spec.shortcutRegistration == .legacy || availability.isEnabled($0.command) }
            .compactMap { makeCommand(for: $0) as? UIKeyCommand }
            .filter { shortcut in
                !remainingCommands.contains {
                    $0.action == shortcut.action && $0.input == shortcut.input && $0.modifierFlags == shortcut.modifierFlags
                }
            }
        return shortcuts + remainingCommands
    }

    func build(_ spec: MainMenuSpec, with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        for identifier in spec.removedMenus {
            builder.remove(menu: identifier)
        }
        for menu in spec.mainMenus {
            let commands = menu.items.map(makeCommand)
            builder.replaceChildren(ofMenu: menu.identifier) { _ in commands }
        }
    }

    func makeCommand(for item: MainMenuSpec.Item) -> UICommand {
        guard let shortcut = item.shortcut else {
            return UICommand(title: item.title, action: item.command.action)
        }
        let command = UIKeyCommand(title: item.title, action: item.command.action,
                                   input: shortcut.input, modifierFlags: shortcut.modifiers)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
}

extension MainMenuCommand {
    var action: Selector {
        switch self {
        case .settings:
            return #selector(MainViewController.keyboardSettings)
        }
    }

    init?(action: Selector) {
        guard let command = Self.allCases.first(where: { $0.action == action }) else { return nil }
        self = command
    }
}
