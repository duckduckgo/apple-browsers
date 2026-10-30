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
    case settings, newTab, newFireTab, voiceSearch, location, closeTab, share, printPage
    case find, stop, reload, showTabs, showPasswords, showDownloads, zoomIn, zoomOut, actualSize
    case newTabOnRight, duplicateTab, previousTab, nextTab, about, feedback
    case selectTab, back, forward, findNext, findPrevious, fire, openLink, openBackgroundLink
}

struct MainMenuSpec {
    enum ShortcutRegistration {
        case legacy
        case responder
        case menu
    }

    struct Context: Equatable {
        var voiceSearchEnabled = false
        var fireModeEnabled = false
    }

    struct Shortcut: Equatable {
        let input: String
        let modifiers: UIKeyModifierFlags
    }

    struct Item {
        let command: MainMenuCommand
        let title: String
        let shortcut: Shortcut?
        let requirement: KeyPath<Context, Bool>?
    }

    struct Menu {
        enum Placement {
            case replaceChildren, appendChildren
        }

        let identifier: UIMenu.Identifier
        let items: [Item]
        var placement: Placement = .replaceChildren
        var submenus: [Menu] = []
        var title = ""
        var inline = false

        var allItems: [Item] { items + submenus.flatMap(\.allItems) }

        func resolved(in context: Context) -> Menu {
            let resolvedItems = items.filter { item in
                item.requirement.map { context[keyPath: $0] } ?? true
            }
            return Menu(identifier: identifier, items: resolvedItems, placement: placement,
                        submenus: submenus.map { $0.resolved(in: context) }, title: title, inline: inline)
        }
    }

    let menus: [Menu]
    let removedMenus: [UIMenu.Identifier]
    private let baselineMenus: [Menu]
    let shortcutRegistration: ShortcutRegistration

    init(isEnabled: Bool, idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom, context: Context = Context()) {
        shortcutRegistration = isEnabled ? (idiom == .pad ? .menu : .responder) : .legacy
        baselineMenus = [Self.settingsMenu(title: UserText.settingsTitle)]
        guard isEnabled else {
            menus = baselineMenus
            removedMenus = []
            return
        }
        removedMenus = shortcutRegistration == .menu ? [.format] : []
        menus = Self.browserMenus.map { $0.resolved(in: context) }
    }

    var mainMenus: [Menu] {
        shortcutRegistration == .menu ? menus : baselineMenus
    }

    var shortcutItems: [Item] {
        allItems.filter { $0.shortcut != nil }
    }

    var allItems: [Item] { menus.flatMap(\.allItems) }

    func remainingKeyCommands(from commands: [UIKeyCommand]) -> [UIKeyCommand] {
        guard shortcutRegistration != .legacy else { return commands }
        return commands.compactMap { command in
            let removedArrow = command.modifierFlags == .command &&
                [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].contains(command.input ?? "")
            guard !removedArrow, command.input != "tap link", !allItems.contains(where: { item in
                item.command.action == command.action && item.shortcut?.input == command.input
                    && item.shortcut?.modifiers == command.modifierFlags
            }) else { return nil }
            guard allItems.contains(where: { $0.command.action == command.action }),
                  let alternate = command.copy() as? UIKeyCommand else { return command }
            alternate.attributes.insert(.hidden)
            return alternate
        }
    }

    static func tabIndex(number: Int, count: Int, menuEnabled: Bool) -> Int? {
        guard (1...9).contains(number), count > 0 else { return nil }
        let index = menuEnabled && number == 9 ? count - 1 : number - 1
        return index < count ? index : nil
    }

    private static func item(_ command: MainMenuCommand, _ title: String,
                             _ input: String? = nil, _ modifiers: UIKeyModifierFlags = [],
                             requires requirement: KeyPath<Context, Bool>? = nil) -> Item {
        Item(command: command, title: title, shortcut: input.map { Shortcut(input: $0, modifiers: modifiers) },
             requirement: requirement)
    }

    private static func group(_ identifier: String, _ items: [Item]) -> Menu {
        Menu(identifier: UIMenu.Identifier("com.duckduckgo." + identifier), items: items, inline: true)
    }

    private static var browserMenus: [Menu] {
        [settingsMenu(title: UserText.menuSettings), fileMenu, editMenu, viewMenu, windowMenu, helpMenu]
    }

    private static func settingsMenu(title: String) -> Menu {
        Menu(identifier: .preferences, items: [item(.settings, title, ",", .command)])
    }

    private static var fileMenu: Menu {
        Menu(identifier: .file, items: [], submenus: [
            group("file.new", [
                item(.newTab, UserText.keyCommandNewTab, "t", .command),
                item(.newFireTab, UserText.keyCommandNewFireTab, "n", [.shift, .command], requires: \.fireModeEnabled),
                item(.voiceSearch, UserText.menuVoiceSearch, ".", [.shift, .command], requires: \.voiceSearchEnabled)
            ]),
            group("file.location", [item(.location, UserText.menuOpenLocation, "l", .command)]),
            group("file.close", [item(.closeTab, UserText.keyCommandCloseTab, "w", .command)]),
            group("file.share", [item(.share, UserText.actionShare)]),
            group("file.print", [item(.printPage, UserText.menuPrint, "p", .command)])
        ])
    }

    private static var editMenu: Menu {
        Menu(identifier: .edit, items: [], placement: .appendChildren, submenus: [
            group("edit.find", [item(.find, UserText.keyCommandFind, "f", .command)])
        ])
    }

    private static var viewMenu: Menu {
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

    private static var windowMenu: Menu {
        Menu(identifier: .window, items: [], placement: .appendChildren, submenus: [
            group("window.tabs", [item(.newTabOnRight, UserText.menuNewTabOnRight),
                                  item(.duplicateTab, UserText.menuDuplicateTab)]),
            group("window.select", [item(.previousTab, UserText.menuPreviousTab, "[", [.shift, .command]),
                                    item(.nextTab, UserText.menuNextTab, "]", [.shift, .command])])
        ])
    }

    private static var helpMenu: Menu {
        Menu(identifier: .help, items: [], placement: .appendChildren, submenus: [
            group("help.about", [item(.about, UserText.settingsAboutDDG),
                                 item(.feedback, UserText.menuFeedback)]),
            Menu(identifier: UIMenu.Identifier("com.duckduckgo.moreShortcuts"), items: moreShortcuts,
                 title: UserText.menuMoreShortcuts)
        ])
    }

    private static var moreShortcuts: [Item] {
        (1...8).map { item(.selectTab, UserText.menuSelectTab($0), String($0), .command) } + [
            item(.selectTab, UserText.menuLastTab, "9", .command),
            item(.nextTab, UserText.keyCommandNextTab, UIKeyCommand.inputTab, .control),
            item(.previousTab, UserText.keyCommandPreviousTab, UIKeyCommand.inputTab, [.control, .shift]),
            item(.back, UserText.menuBack, "[", .command), item(.forward, UserText.menuForward, "]", .command),
            item(.findNext, UserText.keyCommandFindNext, "g", .command),
            item(.findPrevious, UserText.keyCommandFindPrevious, "g", [.shift, .command]),
            item(.showTabs, UserText.menuShowTabs, "\\", [.control, .shift]),
            item(.showTabs, UserText.menuShowTabs, UIKeyCommand.inputTab, [.alternate, .command]),
            item(.openLink, UserText.menuOpenLink),
            item(.openBackgroundLink, UserText.menuOpenBackgroundLink),
            item(.fire, UserText.menuClearTabsAndData, UIKeyCommand.inputBackspace, [.control, .alternate])
        ]
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
