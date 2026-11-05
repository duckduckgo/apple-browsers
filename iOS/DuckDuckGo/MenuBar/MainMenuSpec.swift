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

import DesignResourcesKitIcons
import UIKit

enum MainMenuCommand: CaseIterable {
    case openDuckAI, newChat, newVoiceChat, newImageChat, openRecentChat, deleteAllChats
    case showBookmarks, addBookmark, addFavorite, importBookmarks, exportBookmarks, openBookmark
    case settings, newTab, newFireTab, voiceSearch, location, closeTab, share, printPage
    case find, stop, reload, showTabs, showPasswords, showDownloads, zoomIn, zoomOut, actualSize
    case newTabOnRight, duplicateTab, previousTab, nextTab, about, feedback
    case selectTab, back, forward, findNext, findPrevious, fire
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
        var aiChatEnabled = false
        var favorites: [MainMenuBookmark] = []
        var isOnboarding = false
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
        /// Passed to the command as its property list, which also tells apart commands that share an action.
        var argument: String?
        var image: UIImage?
    }

    struct Menu {
        enum Placement: Equatable {
            enum Position {
                case before, after
            }

            case replaceChildren
            case insert(sibling: UIMenu.Identifier, position: Position)
        }

        let identifier: UIMenu.Identifier
        var items: [Item]
        var placement: Placement = .replaceChildren
        var submenus: [Menu] = []
        /// Title of a top level menu or a submenu; a submenu without one is an inline group.
        var title: String?
        /// Marks where the `MainMenuDeferredContent` registered for this identifier goes.
        var deferredContent: UIMenu.Identifier?

        var allItems: [Item] { items + submenus.flatMap(\.allItems) }

        func resolved(in context: Context) -> Menu {
            var menu = self
            menu.items = items.filter { item in
                item.requirement.map { context[keyPath: $0] } ?? true
            }
            menu.submenus = submenus.map { $0.resolved(in: context) }
            return menu
        }
    }

    /// A menu together with the section that builds it.
    struct Entry {
        let menu: Menu
        let section: MainMenuSection
    }

    private static func systemHasMenuBar(idiom: UIUserInterfaceIdiom) -> Bool {
        guard idiom == .pad, #available(iOS 26.0, *) else { return false }
        return true
    }

    private static var browserSections: [MainMenuSection] {
        [SettingsMenuSection(title: UserText.menuSettings, image: DesignSystemImages.Glyphs.Size16.settings), FileMenuSection(), EditMenuSection(),
         ViewMenuSection(), DuckAIMenuSection(), BookmarksMenuSection(), WindowMenuSection(), HelpMenuSection()]
    }

    private static var baselineSections: [MainMenuSection] {
        [SettingsMenuSection(title: UserText.settingsTitle)]
    }

    private let entries: [Entry]
    private let baselineEntries: [Entry]
    /// Shortcuts without a menu item; iPadOS lists them in its own Help > More Keyboard Shortcuts.
    let keyCommandItems: [Item]
    let removedMenus: [UIMenu.Identifier]
    let shortcutRegistration: ShortcutRegistration

    init(isEnabled: Bool, idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom, context: Context = Context()) {
        shortcutRegistration = isEnabled ? (Self.systemHasMenuBar(idiom: idiom) ? .menu : .responder) : .legacy
        baselineEntries = Self.entries(of: Self.baselineSections, in: context)
        guard isEnabled else {
            entries = baselineEntries
            keyCommandItems = []
            removedMenus = []
            return
        }
        keyCommandItems = Self.keyCommandOnlyItems
        // Onboarding offers none of the browser's commands, so the menu bar shows only the system's own menus.
        guard shortcutRegistration != .menu || !context.isOnboarding else {
            entries = []
            removedMenus = [.format, .file, .view]
            return
        }
        removedMenus = shortcutRegistration == .menu ? [.format] : []
        entries = Self.entries(of: Self.browserSections, in: context)
    }

    private static func entries(of sections: [MainMenuSection], in context: Context) -> [Entry] {
        sections.compactMap { section in
            section.menu(in: context).map { Entry(menu: $0.resolved(in: context), section: section) }
        }
    }

    var menus: [Menu] { entries.map(\.menu) }

    var mainEntries: [Entry] {
        shortcutRegistration == .menu ? entries : baselineEntries
    }

    var mainMenus: [Menu] { mainEntries.map(\.menu) }

    var shortcutItems: [Item] {
        allItems.filter { $0.shortcut != nil }
    }

    var allItems: [Item] { menus.flatMap(\.allItems) + keyCommandItems }

    func remainingKeyCommands(from commands: [UIKeyCommand]) -> [UIKeyCommand] {
        guard shortcutRegistration != .legacy else { return commands }
        return commands.compactMap { command in
            let removedArrow = command.modifierFlags == .command &&
                [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].contains(command.input ?? "")
            guard !removedArrow, !allItems.contains(where: { item in
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

    static func item(_ command: MainMenuCommand, _ title: String,
                     _ input: String? = nil, _ modifiers: UIKeyModifierFlags = [],
                     requires requirement: KeyPath<Context, Bool>? = nil, image: UIImage? = nil) -> Item {
        Item(command: command, title: title, shortcut: input.map { Shortcut(input: $0, modifiers: modifiers) },
             requirement: requirement, image: image)
    }

    static func group(_ identifier: String, _ items: [Item]) -> Menu {
        Menu(identifier: UIMenu.Identifier("com.duckduckgo." + identifier), items: items)
    }

    private static var keyCommandOnlyItems: [Item] {
        (1...8).map { item(.selectTab, UserText.menuSelectTab($0), String($0), .command) } + [
            item(.selectTab, UserText.menuLastTab, "9", .command),
            item(.nextTab, UserText.keyCommandNextTab, UIKeyCommand.inputTab, .control),
            item(.previousTab, UserText.keyCommandPreviousTab, UIKeyCommand.inputTab, [.control, .shift]),
            item(.back, UserText.menuBack, "[", .command), item(.forward, UserText.menuForward, "]", .command),
            item(.findNext, UserText.keyCommandFindNext, "g", .command),
            item(.findPrevious, UserText.keyCommandFindPrevious, "g", [.shift, .command]),
            item(.fire, UserText.menuClearTabsAndData, UIKeyCommand.inputBackspace, [.control, .alternate])
        ]
    }
}

extension MainMenuCommand {
    var action: Selector {
        switch self {
        case .openDuckAI: return #selector(MainViewController.menuOpenDuckAI)
        case .newChat: return #selector(MainViewController.menuNewChat)
        case .newVoiceChat: return #selector(MainViewController.menuNewVoiceChat)
        case .newImageChat: return #selector(MainViewController.menuNewImageChat)
        case .openRecentChat: return #selector(MainViewController.menuOpenRecentChat(_:))
        case .deleteAllChats: return #selector(MainViewController.menuDeleteAllChats(_:))
        case .showBookmarks: return #selector(MainViewController.menuToggleBookmarks)
        case .addBookmark: return #selector(MainViewController.keyboardAddBookmark)
        case .addFavorite: return #selector(MainViewController.keyboardAddFavorite)
        case .importBookmarks: return #selector(MainViewController.menuImportBookmarks)
        case .exportBookmarks: return #selector(MainViewController.menuExportBookmarks)
        case .openBookmark: return #selector(MainViewController.menuOpenBookmark(_:))
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
        }
    }

    init?(action: Selector) {
        guard let command = Self.allCases.first(where: { $0.action == action }) else { return nil }
        self = command
    }
}
