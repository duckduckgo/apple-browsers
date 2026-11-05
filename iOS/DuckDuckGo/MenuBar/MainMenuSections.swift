//
//  MainMenuSections.swift
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

import DesignResourcesKitIcons
import UIKit

/// One top level menu of the main menu.
protocol MainMenuSection {
    /// The menu to show in the given context, or `nil` to hide the whole menu.
    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu?

    /// The children to install, given the elements built from `menu(in:)` and the system menu's own, which an inserted menu has none of.
    func children(of elements: [UIMenuElement], systemElements: [UIMenuElement]) -> [UIMenuElement]
}

extension MainMenuSection {
    func children(of elements: [UIMenuElement], systemElements: [UIMenuElement]) -> [UIMenuElement] {
        elements
    }
}

/// Provides the content of a deferred menu placeholder, built each time the menu opens.
protocol MainMenuDeferredContent {
    func makeElement() -> UIDeferredMenuElement
}

private typealias Item = MainMenuSpec.Item
private typealias Menu = MainMenuSpec.Menu
private typealias Glyphs = DesignSystemImages.Glyphs.Size16

private extension MainMenuSection {
    func item(_ command: MainMenuCommand, _ title: String,
              _ input: String? = nil, _ modifiers: UIKeyModifierFlags = [],
              requires requirement: KeyPath<MainMenuSpec.Context, Bool>? = nil, image: UIImage? = nil) -> Item {
        MainMenuSpec.item(command, title, input, modifiers, requires: requirement, image: image)
    }

    func group(_ identifier: String, _ items: [Item]) -> Menu {
        MainMenuSpec.group(identifier, items)
    }
}

struct SettingsMenuSection: MainMenuSection {
    let title: String
    var image: UIImage?
    var includesAppItems = false

    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        let appItems = [item(.setDefaultBrowser, UserText.menuSetDefaultBrowser),
                        item(.addToDock, UserText.menuAddToDock),
                        item(.addWidget, UserText.menuAddWidget)]
        return Menu(identifier: .preferences, items: [item(.settings, title, ",", .command, image: image)],
                    submenus: includesAppItems ? [group("app.setup", appItems)] : [])
    }
}

struct FileMenuSection: MainMenuSection {
    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        Menu(identifier: .file, items: [], submenus: [
            group("file.new", [
                item(.newTab, UserText.keyCommandNewTab, "t", .command, image: Glyphs.add),
                item(.newFireTab, UserText.keyCommandNewFireTab, "n", [.shift, .command], requires: \.fireModeEnabled,
                     image: Glyphs.fireWindow),
                item(.voiceSearch, UserText.menuVoiceSearch, ".", [.shift, .command], requires: \.voiceSearchEnabled,
                     image: Glyphs.permissionMicrophone)
            ]),
            group("file.import", [item(.importData, UserText.menuImportBookmarksAndPasswords)]),
            group("file.location", [item(.location, UserText.menuOpenLocation, "l", .command)]),
            group("file.close", [item(.closeTab, UserText.keyCommandCloseTab, "w", .command)]),
            group("file.share", [item(.share, UserText.actionShare, image: Glyphs.shareApple)]),
            group("file.print", [item(.printPage, UserText.menuPrint, "p", .command, image: Glyphs.print)])
        ])
    }
}

struct EditMenuSection: MainMenuSection {
    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        Menu(identifier: .edit, items: [], submenus: [
            group("edit.find", [item(.find, UserText.keyCommandFind, "f", .command, image: Glyphs.findInPage)])
        ])
    }

    /// Puts the first element (Find in Page) where the system Find submenu was and appends the rest.
    func children(of elements: [UIMenuElement], systemElements: [UIMenuElement]) -> [UIMenuElement] {
        guard let findInPage = elements.first else { return systemElements }
        var replacedFind = false
        let updated = replacingFind(in: systemElements, with: findInPage, replaced: &replacedFind)
        return replacedFind ? updated + elements.dropFirst() : systemElements + elements
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
}

struct ViewMenuSection: MainMenuSection {
    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        Menu(identifier: .view, items: [], submenus: [
            group("view.loading", [item(.stop, UserText.menuStop, ".", .command),
                                   item(.reload, UserText.keyCommandReload, "r", .command)]),
            group("view.panels", [item(.showTabs, UserText.menuShowTabs, "\\", [.shift, .command]),
                                  item(.showPasswords, UserText.menuShowPasswords, "a", [.shift, .command]),
                                  item(.showDownloads, UserText.menuShowDownloads, "j", [.shift, .command])]),
            group("view.zoom", [item(.zoomIn, UserText.keyCommandZoomIn, "+", .command),
                                item(.zoomOut, UserText.keyCommandZoomOut, "-", .command),
                                item(.actualSize, UserText.menuActualSize, "0", .command)])
        ])
    }
}

struct WindowMenuSection: MainMenuSection {
    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        Menu(identifier: .window, items: [], submenus: [
            group("window.tabs", [item(.newTabOnRight, UserText.menuNewTabOnRight),
                                  item(.duplicateTab, UserText.menuDuplicateTab)]),
            group("window.select", [item(.previousTab, UserText.menuPreviousTab, "[", [.shift, .command]),
                                    item(.nextTab, UserText.menuNextTab, "]", [.shift, .command])])
        ])
    }

    /// Drops the system Close shortcut, which File > Close Tab owns.
    func children(of elements: [UIMenuElement], systemElements: [UIMenuElement]) -> [UIMenuElement] {
        removingCloseShortcut(from: systemElements) + elements
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
}

struct HelpMenuSection: MainMenuSection {
    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        Menu(identifier: .help, items: [], submenus: [
            group("help.about", [item(.about, UserText.settingsAboutDDG, image: Glyphs.info),
                                 item(.feedback, UserText.menuFeedback, image: Glyphs.feedback)])
        ])
    }

    func children(of elements: [UIMenuElement], systemElements: [UIMenuElement]) -> [UIMenuElement] {
        systemElements + elements
    }
}
