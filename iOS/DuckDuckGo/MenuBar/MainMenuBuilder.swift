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
    /// Fills the placeholders that menus mark with `Menu.deferredContent`.
    var deferredContent: [UIMenu.Identifier: MainMenuDeferredContent] = [:]

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
        for entry in spec.mainEntries {
            let elements = makeElements(for: entry.menu)
            switch entry.menu.placement {
            case .replaceChildren:
                builder.replaceChildren(ofMenu: entry.menu.identifier) { systemElements in
                    entry.section.children(of: elements, systemElements: systemElements)
                }
            case .insert(let sibling, let position):
                insert(entry.menu, children: entry.section.children(of: elements, systemElements: []),
                       next: sibling, position: position, into: builder)
            }
        }
    }

    private func insert(_ menu: MainMenuSpec.Menu, children: [UIMenuElement], next sibling: UIMenu.Identifier,
                        position: MainMenuSpec.Menu.Placement.Position, into builder: UIMenuBuilder) {
        let newMenu = UIMenu(title: menu.title ?? "", identifier: menu.identifier, children: children)
        switch position {
        case .before: builder.insertSibling(newMenu, beforeMenu: sibling)
        case .after: builder.insertSibling(newMenu, afterMenu: sibling)
        }
    }

    private func makeElements(for menu: MainMenuSpec.Menu) -> [UIMenuElement] {
        let commands: [UIMenuElement] = menu.items.map(makeCommand)
        return commands + makeDeferredElements(for: menu) + menu.submenus.map(makeSubmenu)
    }

    private func makeDeferredElements(for menu: MainMenuSpec.Menu) -> [UIMenuElement] {
        guard let identifier = menu.deferredContent, let content = deferredContent[identifier] else { return [] }
        return [content.makeElement()]
    }

    private func makeSubmenu(for menu: MainMenuSpec.Menu) -> UIMenu {
        UIMenu(title: menu.title ?? "", identifier: menu.identifier,
               options: menu.title == nil ? .displayInline : [], children: makeElements(for: menu))
    }

    func makeCommand(for item: MainMenuSpec.Item) -> UICommand {
        guard let shortcut = item.shortcut else {
            return UICommand(title: item.title, image: item.image, action: item.command.action, propertyList: item.argument)
                .showingImage()
        }
        let propertyList: Any = item.argument ?? ["input": shortcut.input, "modifiers": shortcut.modifiers.rawValue]
        let command = UIKeyCommand(title: item.title, image: item.image, action: item.command.action,
                                   input: shortcut.input, modifierFlags: shortcut.modifiers, propertyList: propertyList)
        command.wantsPriorityOverSystemBehavior = true
        return command.showingImage()
    }
}

extension UIMenuElement {

    /// Makes the element's image show on iOS 27, which hides menu images unless an element asks for them.
    @discardableResult
    func showingImage() -> Self {
        if #available(iOS 27.0, *), image != nil {
            preferredImageVisibility = .visible
        }
        return self
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
