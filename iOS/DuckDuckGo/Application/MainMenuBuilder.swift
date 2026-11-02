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

    /// Titled key commands for shortcuts that have no menu item, when the menu bar owns shortcut registration.
    func keyCommandOnlyCommands(for spec: MainMenuSpec) -> [UIKeyCommand] {
        guard spec.shortcutRegistration == .menu else { return [] }
        return spec.keyCommandItems.compactMap { makeCommand(for: $0) as? UIKeyCommand }
    }

    func build(_ spec: MainMenuSpec, with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        spec.removedMenus.forEach { builder.remove(menu: $0) }
        for menu in spec.mainMenus {
            let elements = makeElements(for: menu)
            builder.replaceChildren(ofMenu: menu.identifier) { systemElements in
                children(of: menu, elements: elements, systemElements: systemElements)
            }
        }
    }

    private func children(of menu: MainMenuSpec.Menu, elements: [UIMenuElement],
                          systemElements: [UIMenuElement]) -> [UIMenuElement] {
        guard menu.placement == .appendChildren else { return elements }
        switch menu.identifier {
        case .edit:
            return replacingSystemFind(in: systemElements, with: elements)
        case .window:
            return removingCloseShortcut(from: systemElements) + elements
        default:
            return systemElements + elements
        }
    }

    /// Puts the first element (Find in Page) where the system Find submenu was and appends the rest.
    private func replacingSystemFind(in systemElements: [UIMenuElement], with elements: [UIMenuElement]) -> [UIMenuElement] {
        guard let findInPage = elements.first else { return systemElements }
        var replacedFind = false
        let updated = replacingFind(in: systemElements, with: findInPage, replaced: &replacedFind)
        return replacedFind ? updated + elements.dropFirst() : systemElements + elements
    }

    private func makeElements(for menu: MainMenuSpec.Menu) -> [UIMenuElement] {
        menu.items.map(makeCommand) + menu.submenus.map { submenu in
            UIMenu(title: "", identifier: submenu.identifier, options: .displayInline, children: makeElements(for: submenu))
        }
    }

    private func removingCloseShortcut(from elements: [UIMenuElement]) -> [UIMenuElement] {
        elements.compactMap { element in
            if let command = element as? UIKeyCommand, command.input == "w", command.modifierFlags == .command {
                guard let action = command.action else { return nil }
                return UICommand(title: command.title, image: command.image, action: action,
                                 propertyList: command.propertyList, attributes: command.attributes, state: command.state)
            }
            if let menu = element as? UIMenu {
                return menu.replacingChildren(removingCloseShortcut(from: menu.children))
            }
            return element
        }
    }

    private func replacingFind(in elements: [UIMenuElement], with replacement: UIMenuElement,
                               replaced: inout Bool) -> [UIMenuElement] {
        elements.map { element in
            guard let menu = element as? UIMenu else { return element }
            if menu.identifier == .find {
                replaced = true
                return replacement
            }
            return menu.replacingChildren(replacingFind(in: menu.children, with: replacement, replaced: &replaced))
        }
    }

    func makeCommand(for item: MainMenuSpec.Item) -> UICommand {
        guard let shortcut = item.shortcut else {
            return UICommand(title: item.title, action: item.command.action)
        }
        let propertyList: [String: Any] = ["input": shortcut.input, "modifiers": shortcut.modifiers.rawValue]
        let command = UIKeyCommand(title: item.title, action: item.command.action,
                                   input: shortcut.input, modifierFlags: shortcut.modifiers, propertyList: propertyList)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
}

extension UICommand {

    func applyMenuState(title: String?, isEnabled: Bool) {
        if let title { self.title = title }
        if isEnabled {
            attributes.remove(.disabled)
        } else {
            attributes.insert(.disabled)
        }
    }

}
