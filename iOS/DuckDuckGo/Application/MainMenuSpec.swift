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

import AIChat
import UIKit

enum MainMenuCommand: CaseIterable {
    case openDuckAI, newChat, newVoiceChat, newImageChat, openRecentChat, deleteAllChats
    case showBookmarks, addBookmark, addFavorite, importBookmarks, exportBookmarks, openBookmark
    case settings, newTab, newFireTab, voiceSearch, location, closeTab, share, printPage
    case find, stop, reload, showTabs, showPasswords, showDownloads, zoomIn, zoomOut, actualSize
    case newTabOnRight, duplicateTab, previousTab, nextTab, about, feedback
    case selectTab, back, forward, findNext, findPrevious, fire, openLink, openBackgroundLink
}

struct MainMenuSpec {
    struct Context: Equatable {
        var voiceSearchEnabled = false
        var fireModeEnabled = false
        var favorites: [MainMenuBookmark] = []
        var aiChatEnabled = false
        var nativeChatsAvailable = false
    }

    struct Shortcut: Equatable {
        let input: String
        let modifiers: UIKeyModifierFlags
    }

    struct Item {
        let command: MainMenuCommand
        let title: String
        let shortcut: Shortcut?
        var url: URL?
        var isFireMode: Bool?
        var chatCount: Int?
    }

    struct Menu {
        enum Placement {
            case replaceChildren, appendChildren
            case insertBefore(UIMenu.Identifier)
        }

        let identifier: UIMenu.Identifier
        let items: [Item]
        var placement: Placement = .replaceChildren
        var submenus: [Menu] = []
        var title = ""
        var inline = false
        var loadsBookmarks = false
        var loadsChats = false

        var allItems: [Item] { items + submenus.flatMap(\.allItems) }
    }

    let menus: [Menu]
    let removedMenus: [UIMenu.Identifier]
    let ownsKeyCommands: Bool

    init(isEnabled: Bool, context: Context = Context()) {
        ownsKeyCommands = isEnabled
        let settings = Menu(identifier: .preferences, items: [
            Self.item(.settings, isEnabled ? UserText.menuSettings : UserText.settingsTitle, ",", .command)
        ])
        guard isEnabled else {
            menus = [settings]
            removedMenus = []
            return
        }
        removedMenus = [.format]
        var newTabs = [Self.item(.newTab, UserText.keyCommandNewTab, "t", .command)]
        if context.fireModeEnabled {
            newTabs.append(Self.item(.newFireTab, UserText.keyCommandNewFireTab, "n", [.shift, .command]))
        }
        if context.voiceSearchEnabled {
            newTabs.append(Self.item(.voiceSearch, UserText.menuVoiceSearch, ".", [.shift, .command]))
        }
        let file = Menu(identifier: .file, items: [], submenus: [
            Self.group("file.new", newTabs),
            Self.group("file.location", [Self.item(.location, UserText.menuOpenLocation, "l", .command)]),
            Self.group("file.close", [Self.item(.closeTab, UserText.keyCommandCloseTab, "w", .command)]),
            Self.group("file.share", [Self.item(.share, UserText.actionShare)]),
            Self.group("file.print", [Self.item(.printPage, UserText.menuPrint, "p", .command)])
        ])
        let edit = Menu(identifier: .edit, items: [], placement: .appendChildren, submenus: [
            Self.group("edit.find", [Self.item(.find, UserText.keyCommandFind, "f", .command)])
        ])
        let view = Menu(identifier: .view, items: [], submenus: [
            Self.group("view.loading", [Self.item(.stop, UserText.menuStop, ".", .command),
                                        Self.item(.reload, UserText.keyCommandReload, "r", .command)]),
            Self.group("view.panels", [Self.item(.showTabs, UserText.menuShowTabs, "\\", [.shift, .command]),
                                       Self.item(.showPasswords, UserText.menuShowPasswords, "a", [.shift, .command]),
                                       Self.item(.showDownloads, UserText.menuShowDownloads, "j", [.shift, .command])]),
            Self.group("view.zoom", [Self.item(.zoomIn, UserText.keyCommandZoomIn, "+", .command),
                                     Self.item(.zoomOut, UserText.keyCommandZoomOut, "-", .command),
                                     Self.item(.actualSize, UserText.menuActualSize, "0", .command)])
        ])
        let window = Menu(identifier: .window, items: [], placement: .appendChildren, submenus: [
            Self.group("window.tabs", [Self.item(.newTabOnRight, UserText.menuNewTabOnRight),
                                       Self.item(.duplicateTab, UserText.menuDuplicateTab)]),
            Self.group("window.select", [Self.item(.previousTab, UserText.menuPreviousTab, "[", [.shift, .command]),
                                         Self.item(.nextTab, UserText.menuNextTab, "]", [.shift, .command])])
        ])
        let help = Menu(identifier: .help, items: [], placement: .appendChildren, submenus: [
            Self.group("help.about", [Self.item(.about, UserText.settingsAboutDDG),
                                      Self.item(.feedback, UserText.menuFeedback)]),
            Menu(identifier: UIMenu.Identifier("com.duckduckgo.moreShortcuts"), items: Self.moreShortcuts,
                 title: UserText.menuMoreShortcuts)
        ])
        let favorites = context.favorites.enumerated().map { index, bookmark in
            Item(command: .openBookmark, title: bookmark.title,
                 shortcut: index < 9 ? Shortcut(input: String(index + 1), modifiers: [.alternate, .command]) : nil,
                 url: bookmark.url)
        }
        let bookmarks = Menu(identifier: UIMenu.Identifier("com.duckduckgo.bookmarks"), items: [],
                             placement: .insertBefore(.window), submenus: [
            Self.group("bookmarks.show", [Self.item(.showBookmarks, UserText.menuShowBookmarks, "k", [.shift, .command])]),
            Self.group("bookmarks.add", [Self.item(.addBookmark, UserText.keyCommandAddBookmark, "d", .command),
                                         Self.item(.addFavorite, UserText.keyCommandAddFavorite, "d", [.control, .command])]),
            Self.group("bookmarks.files", [Self.item(.importBookmarks, UserText.menuImportBookmarks),
                                           Self.item(.exportBookmarks, UserText.menuExportBookmarks)]),
            Menu(identifier: UIMenu.Identifier("com.duckduckgo.bookmarks.favorites"), items: favorites,
                 title: UserText.menuFavorites),
            Menu(identifier: UIMenu.Identifier("com.duckduckgo.bookmarks.tree"), items: [], inline: true, loadsBookmarks: true)
        ], title: UserText.menuBookmarks)
        var duckAI: [Menu] = []
        if context.aiChatEnabled {
            var groups = [Self.group("duckai.open", [Self.item(.openDuckAI, UserText.menuOpenDuckAI)]),
                          Self.group("duckai.new", [Self.item(.newChat, UserText.menuNewChat, "n", [.alternate, .command]),
                                                    Self.item(.newVoiceChat, UserText.menuNewVoiceChat, "v", [.alternate, .command]),
                                                    Self.item(.newImageChat, UserText.menuNewImageChat, "g", [.alternate, .command])])]
            if context.nativeChatsAvailable {
                groups.append(Menu(identifier: UIMenu.Identifier("com.duckduckgo.duckai.history"), items: [], inline: true, loadsChats: true))
            }
            duckAI = [Menu(identifier: UIMenu.Identifier("com.duckduckgo.duckai"), items: [],
                           placement: .insertBefore(UIMenu.Identifier("com.duckduckgo.bookmarks")), submenus: groups,
                           title: "Duck.ai")]
        }
        menus = [settings, file, edit, view, bookmarks] + duckAI + [window, help]
    }

    static func chatHistoryMenus(snapshot: MainMenuAIChats.Snapshot, aiChatURL: URL, isFireMode: Bool) -> [Menu] {
        let items = snapshot.recent.map {
            Item(command: .openRecentChat, title: $0.title, shortcut: nil,
                 url: aiChatURL.withChatID($0.id), isFireMode: isFireMode)
        }
        var menus: [Menu] = []
        if !items.isEmpty {
            menus.append(Menu(identifier: UIMenu.Identifier("com.duckduckgo.duckai.recent"), items: items,
                              title: UserText.menuRecentChats, inline: true))
        }
        menus.append(group("duckai.delete", [Item(command: .deleteAllChats, title: UserText.menuDeleteAllChats,
                                                  shortcut: nil, isFireMode: isFireMode, chatCount: snapshot.totalCount)]))
        return menus
    }

    var allItems: [Item] { menus.flatMap(\.allItems) }

    func remainingKeyCommands(from commands: [UIKeyCommand]) -> [UIKeyCommand] {
        guard ownsKeyCommands else { return commands }
        return commands.compactMap { command in
            let removedArrow = command.modifierFlags == .command &&
                [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].contains(command.input ?? "")
            guard !removedArrow, command.input != "tap link", !allItems.contains(where: { item in
                item.shortcut?.input == command.input && item.shortcut?.modifiers == command.modifierFlags
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
                             _ input: String? = nil, _ modifiers: UIKeyModifierFlags = []) -> Item {
        Item(command: command, title: title, shortcut: input.map { Shortcut(input: $0, modifiers: modifiers) })
    }

    private static func group(_ identifier: String, _ items: [Item]) -> Menu {
        Menu(identifier: UIMenu.Identifier("com.duckduckgo." + identifier), items: items, inline: true)
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
