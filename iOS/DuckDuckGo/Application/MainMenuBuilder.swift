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

import DesignResourcesKitIcons
import UIKit

struct MainMenuBuilder {
    var chatHistory: (@escaping ([MainMenuSpec.Menu]) -> Void) -> Void = { $0([]) }
    var bookmarkChildren: (String?) -> [MainMenuBookmarkEntry] = { _ in [] }
    var iconPolicy: MainMenuSpec.IconPolicy = .legacy

    func build(_ spec: MainMenuSpec, with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        var configured = self
        configured.iconPolicy = spec.iconPolicy
        if spec.iconPolicy == .design {
            builder.replaceChildren(ofMenu: .application) { existing in
                configured.hidingSystemImages(in: existing)
            }
        }
        for identifier in spec.removedMenus {
            builder.remove(menu: identifier)
        }
        for menu in spec.menus {
            let elements = configured.makeElements(for: menu)
            if case .insertBefore(let sibling) = menu.placement {
                builder.insertSibling(UIMenu(title: menu.title, identifier: menu.identifier, children: elements), beforeMenu: sibling)
                continue
            }
            builder.replaceChildren(ofMenu: menu.identifier) { existing in
                let windowItems = menu.identifier == .window && spec.ownsKeyCommands ? removingCloseShortcut(from: existing) : existing
                let retained = [.edit, .window].contains(menu.identifier) ? configured.hidingSystemImages(in: windowItems) : windowItems
                if menu.identifier == .edit, spec.ownsKeyCommands {
                    var replacedFind = false
                    let updated = replacingFind(in: retained, with: elements[0], replaced: &replacedFind)
                    return updated + (replacedFind ? Array(elements.dropFirst()) : elements)
                }
                if case .appendChildren = menu.placement { return retained + elements }
                return elements
            }
        }
    }

    private func makeElements(for menu: MainMenuSpec.Menu) -> [UIMenuElement] {
        let deferred: [UIMenuElement] = menu.loadsBookmarks ? [makeBookmarkFolder()] : []
        let chats: [UIMenuElement] = menu.loadsChats ? [makeChatHistory()] : []
        return menu.items.map(makeCommand) + deferred + chats + menu.submenus.map(makeMenu)
    }

    func makeChatHistory() -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { completion in
            chatHistory { menus in
                completion(menus.map { menu in
                    makeMenu(menu)
                })
            }
        }
    }

    func makeBookmarkFolder(id: String? = nil) -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { completion in
            DispatchQueue.main.async {
                let elements: [UIMenuElement] = bookmarkChildren(id).map { entry in
                    switch entry {
                    case .bookmark(let bookmark):
                        return makeCommand(for: .init(command: .openBookmark, title: bookmark.title, shortcut: nil, url: bookmark.url))
                    case .folder(let title, let folderID):
                        return makeBookmarkSubmenu(title: title, id: folderID)
                    }
                }
                completion(elements)
            }
        }
    }

    private func makeMenu(_ menu: MainMenuSpec.Menu) -> UIMenu {
        let result = UIMenu(title: menu.title, identifier: menu.identifier,
                            options: menu.inline ? .displayInline : [], children: makeElements(for: menu))
        applyImageVisibility(to: result)
        return result
    }

    func makeBookmarkSubmenu(title: String, id: String) -> UIMenu {
        let menu = UIMenu(title: title, image: DesignSystemImages.Color.Size16.folder,
                          children: [makeBookmarkFolder(id: id)])
        applyImageVisibility(to: menu)
        return menu
    }

    private func hidingSystemImages(in elements: [UIMenuElement]) -> [UIMenuElement] {
        guard iconPolicy == .design else { return elements }
        return elements.map { element in
            let result = (element as? UIMenu).map { $0.replacingChildren(hidingSystemImages(in: $0.children)) } ?? element
            if #available(iOS 27.0, *) {
                result.preferredImageVisibility = .hidden
            }
            return result
        }
    }

    private func applyImageVisibility(to element: UIMenuElement) {
        if iconPolicy == .design, #available(iOS 27.0, *) {
            element.preferredImageVisibility = element.image == nil ? .hidden : .visible
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

    private func favicon(for item: MainMenuSpec.Item) -> UIImage? {
        guard item.command == .openBookmark, let url = item.url else { return nil }
        return FaviconsHelper.loadFaviconSync(forDomain: url.host, usingCache: .fireproof, useFakeFavicon: true).image
    }

    func makeCommand(for item: MainMenuSpec.Item) -> UICommand {
        let propertyList: Any?
        if let isFireMode = item.isFireMode {
            propertyList = MainMenuAIChatPayload(isFireMode: isFireMode, url: item.url, chatCount: item.chatCount).propertyList
        } else if let url = item.url {
            propertyList = url.absoluteString
        } else if let shortcut = item.shortcut {
            propertyList = ["input": shortcut.input, "modifiers": shortcut.modifiers.rawValue]
        } else {
            propertyList = nil
        }
        let image = item.command == .openBookmark ? favicon(for: item) : image(for: item.command)
        let command: UICommand
        if let shortcut = item.shortcut {
            let keyCommand = UIKeyCommand(title: item.title, image: image, action: item.command.action,
                                         input: shortcut.input, modifierFlags: shortcut.modifiers, propertyList: propertyList)
            keyCommand.wantsPriorityOverSystemBehavior = true
            command = keyCommand
        } else {
            command = UICommand(title: item.title, image: image, action: item.command.action, propertyList: propertyList)
        }
        applyImageVisibility(to: command)
        return command
    }

    private func image(for command: MainMenuCommand) -> UIImage? {
        typealias Glyphs = DesignSystemImages.Glyphs.Size16
        if iconPolicy == .legacy { return nil }
        if iconPolicy == .system, let symbol = command.standardSymbol {
            return UIImage(systemName: symbol)
        }
        switch command {
        case .settings: return Glyphs.settings
        case .newTab: return Glyphs.add
        case .newFireTab: return Glyphs.fireWindow
        case .voiceSearch: return Glyphs.permissionMicrophone
        case .share: return Glyphs.shareApple
        case .printPage: return Glyphs.print
        case .find: return Glyphs.findInPage
        case .openRecentChat: return Glyphs.chat
        case .deleteAllChats: return Glyphs.fire
        case .about: return Glyphs.info
        case .feedback: return Glyphs.feedback
        default: return nil
        }
    }

}

extension MainMenuCommand {
    fileprivate var standardSymbol: String? {
        switch self {
        case .settings: return "gear"
        case .newTab: return "plus"
        case .location: return "location"
        case .closeTab: return "xmark"
        case .share: return "square.and.arrow.up"
        case .printPage: return "printer"
        case .find: return "doc.text.magnifyingglass"
        case .stop: return "xmark"
        case .reload: return "arrow.clockwise"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .actualSize: return "1.magnifyingglass"
        default: return nil
        }
    }

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
        case .openLink: return #selector(MainViewController.menuOpenLink)
        case .openBackgroundLink: return #selector(MainViewController.menuOpenBackgroundLink)
        }
    }

    init?(action: Selector) {
        guard let command = Self.allCases.first(where: { $0.action == action }) else { return nil }
        self = command
    }
}
