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
            let elements = makeElements(for: menu)
            builder.replaceChildren(ofMenu: menu.identifier) { existing in
                let retained = menu.identifier == .window && spec.shortcutRegistration == .menu ? removingCloseShortcut(from: existing) : existing
                if menu.identifier == .edit, spec.shortcutRegistration == .menu {
                    var replacedFind = false
                    let updated = replacingFind(in: retained, with: elements[0], replaced: &replacedFind)
                    return updated + (replacedFind ? Array(elements.dropFirst()) : elements)
                }
                return menu.placement == .appendChildren ? retained + elements : elements
            }
        }
    }

    private func makeElements(for menu: MainMenuSpec.Menu) -> [UIMenuElement] {
        menu.items.map(makeCommand) + menu.submenus.map { submenu in
            UIMenu(title: submenu.title, identifier: submenu.identifier,
                   options: submenu.inline ? .displayInline : [], children: makeElements(for: submenu))
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

extension MainMenuCommand {
    var action: Selector {
        switch self {
        case .settings: return #selector(MainViewController.keyboardSettings)
        case .newTab: return #selector(MainViewController.keyboardNewTab)
        case .newFireTab: return #selector(MainViewController.keyboardNewFireTab)
        case .voiceSearch: return #selector(MainViewController.menuVoiceSearch)
        case .location: return #selector(MainViewController.keyboardLocation)
        case .closeTab: return #selector(MainViewController.keyboardCloseTab)
        case .share: return #selector(MainViewController.menuShare)
        case .printPage: return #selector(MainViewController.keyboardPrint)
        case .find: return #selector(MainViewController.keyboardFind)
        case .stop: return #selector(MainViewController.menuStop)
        case .reload: return #selector(MainViewController.keyboardReload)
        case .showTabs: return #selector(MainViewController.keyboardShowAllTabs)
        case .showPasswords: return #selector(MainViewController.menuTogglePasswords)
        case .showDownloads: return #selector(MainViewController.menuToggleDownloads)
        case .zoomIn: return #selector(MainViewController.keyboardZoomIn)
        case .zoomOut: return #selector(MainViewController.keyboardZoomOut)
        case .actualSize: return #selector(MainViewController.keyboardZoomReset)
        case .newTabOnRight: return #selector(MainViewController.menuNewTabOnRight)
        case .duplicateTab: return #selector(MainViewController.menuDuplicateTab)
        case .previousTab: return #selector(MainViewController.keyboardPreviousTab)
        case .nextTab: return #selector(MainViewController.keyboardNextTab)
        case .about: return #selector(MainViewController.menuAbout)
        case .feedback: return #selector(MainViewController.menuFeedback)
        case .selectTab: return #selector(MainViewController.keyboardSelectTab(_:))
        case .back: return #selector(MainViewController.keyboardBrowserBack)
        case .forward: return #selector(MainViewController.keyboardBrowserForward)
        case .findNext: return #selector(MainViewController.keyboardFindNext)
        case .findPrevious: return #selector(MainViewController.keyboardFindPrevious)
        case .fire: return #selector(MainViewController.keyboardFire)
        case .openLink: return #selector(MainViewController.menuOpenLink)
        case .openBackgroundLink: return #selector(MainViewController.menuOpenBackgroundLink)
        }
    }

    init?(action: Selector) {
        guard let command = Self.allCases.first(where: { $0.action == action }) else { return nil }
        self = command
    }
}
