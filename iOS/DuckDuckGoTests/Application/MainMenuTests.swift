//
//  MainMenuTests.swift
//  DuckDuckGoTests
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

import Bookmarks
import Core
import CoreData
import FeatureFlags_iOS
import Persistence
import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
struct MainMenuTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [UIUserInterfaceIdiom.phone, .pad])
    func sharedShortcutRegistrationMatchesFlagAndDevice(enabled: Bool, idiom: UIUserInterfaceIdiom) throws {
        let spec = MainMenuSpec(isEnabled: enabled, idiom: idiom)
        let availability = MenuCommandAvailability(state: .init(shortcutsEnabled: true, presentation: .browser))
        let commands = MainMenuBuilder().keyCommands(for: spec, from: [], availability: availability)
        let inMenuBar = registersInMenuBar(enabled: enabled, idiom: idiom)
        if inMenuBar {
            #expect(spec.shortcutRegistration == .menu)
            #expect(commands.isEmpty)
        } else {
            #expect(spec.shortcutRegistration == (enabled ? .responder : .legacy))
            let settings = try #require(commands.first)
            let expectedItems = spec.shortcutItems.filter { !enabled || availability.isEnabled($0.command) }
            #expect(commands.count == expectedItems.count)
            #expect(settings.action == #selector(MainViewController.keyboardSettings))
            #expect(settings.input == ",")
            #expect(settings.modifierFlags == .command)
            #expect(settings.wantsPriorityOverSystemBehavior)
            if enabled {
                for (action, input) in [(MainMenuCommand.newTab.action, "t"), (MainMenuCommand.location.action, "l"),
                                        (MainMenuCommand.fire.action, UIKeyCommand.inputBackspace)] {
                    #expect(commands.contains { $0.action == action && $0.input == input })
                }
            }
        }
        #expect(spec.removedMenus == (inMenuBar ? [.format] : []))
        #expect(spec.mainMenus.map(\.identifier) == (inMenuBar ? spec.menus.map(\.identifier) : [.preferences]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true],
          [MenuCommandAvailability.State.Presentation.browser, .tabSwitcher, .blockingModal])
    func phoneShortcutsRespectSharedAvailability(shortcutsEnabled: Bool,
                                                 presentation: MenuCommandAvailability.State.Presentation) {
        let availability = MenuCommandAvailability(state: .init(shortcutsEnabled: shortcutsEnabled, presentation: presentation))
        let settings = UIKeyCommand(title: "Legacy settings", action: #selector(MainViewController.keyboardSettings),
                                    input: ",", modifierFlags: .command)
        for enabled in [false, true, false] {
            let spec = MainMenuSpec(isEnabled: enabled, idiom: .phone)
            let commands = MainMenuBuilder().keyCommands(for: spec, from: [settings], availability: availability)
            let shouldRegister = !enabled || (shortcutsEnabled && presentation != .blockingModal)
            let sharedSettings = commands.filter { $0.action == #selector(MainViewController.keyboardSettings) }
            #expect(sharedSettings.count == (shouldRegister ? 1 : 0))
            let expectedItems = spec.shortcutItems.filter { !enabled || availability.isEnabled($0.command) }
            #expect(commands.count == expectedItems.count)
            if !enabled {
                #expect(commands.first === settings)
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [UIUserInterfaceIdiom.phone, .pad])
    func composerDoesNotDuplicateSharedShortcutOrRemoveLegacyAliases(enabled: Bool, idiom: UIUserInterfaceIdiom) {
        let spec = MainMenuSpec(isEnabled: enabled, idiom: idiom)
        let settings = UIKeyCommand(title: "Legacy settings", action: #selector(MainViewController.keyboardSettings),
                                    input: ",", modifierFlags: .command)
        let alternate = UIKeyCommand(title: "Settings alternate", action: #selector(MainViewController.keyboardSettings),
                                     input: ",", modifierFlags: [.command, .shift])
        let otherAction = UIKeyCommand(title: "Other action", action: #selector(MainViewController.keyboardReload),
                                       input: ",", modifierFlags: .command)
        let availability = MenuCommandAvailability(state: .init(shortcutsEnabled: true, presentation: .browser))
        let commands = MainMenuBuilder().keyCommands(for: spec, from: [settings, alternate, otherAction], availability: availability)
        for original in [alternate, otherAction] {
            let retained = commands.first { $0.action == original.action && $0.input == original.input && $0.modifierFlags == original.modifierFlags }
            #expect(retained != nil)
            #expect(retained?.attributes.contains(.hidden) == enabled)
            #expect(!original.attributes.contains(.hidden))
        }
        let shared = commands.filter {
            $0.action == #selector(MainViewController.keyboardSettings) && $0.input == "," && $0.modifierFlags == .command
        }
        let inMenuBar = registersInMenuBar(enabled: enabled, idiom: idiom)
        #expect(shared.count == (inMenuBar ? 0 : 1))
        let sharedItems = inMenuBar ? [] : spec.shortcutItems.filter { !enabled || availability.isEnabled($0.command) }
        #expect(commands.count == sharedItems.count + 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func flagUpdatesRebuildOffOnOffAndIgnoreUnchangedValues() async throws {
        let flagger = MockFeatureFlagger()
        var rebuildCount = 0
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        let service = MainMenuService(featureFlagger: flagger, idiom: .pad,
                                      rebuildDelay: .milliseconds(1)) {
            rebuildCount += 1
            continuation.yield(())
        }
        #expect(service.spec.removedMenus.isEmpty)
        for enabled in [true, false] {
            flagger.enabledFeatureFlags = enabled ? [.ipadMenuBar] : []
            flagger.triggerUpdate()
            _ = await iterator.next()
            #expect(service.spec.removedMenus == (registersInMenuBar(enabled: enabled, idiom: .pad) ? [.format] : []))
        }
        #expect(rebuildCount == 2)
        flagger.triggerUpdate()
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iPhoneDoesNotRebuildWhenIPadFlagChanges() async throws {
        let flagger = MockFeatureFlagger()
        var rebuildCount = 0
        let service = MainMenuService(featureFlagger: flagger, idiom: .phone,
                                      rebuildDelay: .milliseconds(1)) { rebuildCount += 1 }
        #expect(service.spec.shortcutRegistration == .legacy)
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        flagger.triggerUpdate()
        service.requestRebuild()
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 0)
        #expect(service.spec.removedMenus.isEmpty)
        #expect(service.spec.shortcutRegistration == .responder)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func menuItemsDoNotShareShortcuts() {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad,
                                context: .init(voiceSearchEnabled: true, fireModeEnabled: true, aiChatEnabled: true))
        let shortcuts = spec.allItems.compactMap(\.shortcut)
        for shortcut in shortcuts {
            #expect(shortcuts.filter { $0 == shortcut }.count == 1)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func menuOwnsEquivalentsAcrossRespondersAndRetainsHiddenAlternates() {
        let make = { (action: Selector, input: String, modifiers: UIKeyModifierFlags) in
            UIKeyCommand(title: "", action: action, input: input, modifierFlags: modifiers)
        }
        let close = make(MainMenuCommand.closeTab.action, "w", .command)
        let newTabAlternate = make(MainMenuCommand.newTab.action, "n", .command)
        let zoomAlternate = make(MainMenuCommand.zoomIn.action, "=", .command)
        let cursor = make(MainMenuCommand.back.action, UIKeyCommand.inputLeftArrow, .command)
        let commands = [close, newTabAlternate, zoomAlternate, cursor]
        for enabled in [false, true, false] {
            let spec = MainMenuSpec(isEnabled: enabled, idiom: .pad)
            let remaining = spec.remainingKeyCommands(from: commands)
            #expect(remaining.map(\.input) == (enabled ? ["n", "="] : commands.map(\.input)))
            #expect(remaining.allSatisfy { $0.attributes.contains(.hidden) } == enabled)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [5, 12])
    func commandNineSelectsLastTabOnlyInNewMode(count: Int) {
        #expect(MainMenuSpec.tabIndex(number: 9, count: count, menuEnabled: true) == count - 1)
        #expect(MainMenuSpec.tabIndex(number: 9, count: count, menuEnabled: false) == (count >= 9 ? 8 : nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func lockedAndBlockingPresentationsDisableCommands() {
        #expect(!MenuCommandAvailability(state: .init(shortcutsEnabled: false, presentation: .browser)).isEnabled(.newTab))
        #expect(!MenuCommandAvailability(state: .init(shortcutsEnabled: true, presentation: .blockingModal)).isEnabled(.newTab))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func duckAIMenuFollowsDuckAISetting(aiChatEnabled: Bool) {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad, context: .init(aiChatEnabled: aiChatEnabled))
        #expect(spec.menus.contains { $0.identifier == DuckAIMenuSection.identifier } == aiChatEnabled)
        #expect(spec.allItems.contains { $0.command == .newChat } == aiChatEnabled)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func duckAICommandsAreDisabledWhenDuckAIIsOff() {
        let state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
        #expect(!MenuCommandAvailability(state: state).isEnabled(.newChat))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func deleteAllChatsStaysVisibleWithoutChats() throws {
        let elements = DuckAIRecentChatsMenuContent.elements(for: .init(recentChats: [], totalChatCount: 0))
        let commands = elements.compactMap { $0 as? UIMenu }.flatMap(\.children).compactMap { $0 as? UICommand }
        #expect(commands.map(\.action) == [MainMenuCommand.deleteAllChats.action])
        let deleteAll = try #require(commands.first)
        #expect(deleteAll.propertyList as? String == "0")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func duckAISettingsChangeRebuildsMenu() async {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        let notificationCenter = NotificationCenter()
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        let service = MainMenuService(featureFlagger: flagger, idiom: .pad, notificationCenter: notificationCenter,
                                      rebuildDelay: .milliseconds(1)) { continuation.yield(()) }
        notificationCenter.post(name: .aiChatSettingsChanged, object: nil)
        _ = await iterator.next()
        withExtendedLifetime(service) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bookmarksMenuOwnsItsShortcutsAndDefersTheTree() {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad, context: .init(favorites: makeFavorites(count: 12)))
        for (command, input, modifiers) in [(MainMenuCommand.showBookmarks, "k", UIKeyModifierFlags([.shift, .command])),
                                            (.addBookmark, "d", .command), (.addFavorite, "d", [.control, .command])] {
            let items = spec.allItems.filter { $0.command == command }
            #expect(items.count == 1)
            #expect(items.first?.shortcut == .init(input: input, modifiers: modifiers))
        }

        var folderFetchCount = 0
        let tree = BookmarksMenuTree(children: { _ in
            folderFetchCount += 1
            return []
        }, favicon: { _ in nil })
        let builder = MainMenuBuilderSpy()
        MainMenuBuilder(deferredContent: [.bookmarksTree: tree]).build(spec, with: builder)
        guard registersInMenuBar(enabled: true, idiom: .pad) else { return }
        #expect(!builder.insertedMenus.isEmpty)
        #expect(folderFetchCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func firstNineFavoritesGetShortcutsCarryingTheirURLs() {
        let favorites = makeFavorites(count: 12)
        let availability = MenuCommandAvailability(state: .init(shortcutsEnabled: true, presentation: .browser))
        let commands = MainMenuBuilder().keyCommands(for: MainMenuSpec(isEnabled: true, idiom: .phone, context: .init(favorites: favorites)),
                                                     from: [], availability: availability)
        let favoriteCommands = commands.filter { $0.action == MainMenuCommand.openBookmark.action }
        #expect(favoriteCommands.map(\.input) == (1...9).map { String($0) })
        #expect(favoriteCommands.allSatisfy { $0.modifierFlags == [.alternate, .command] })
        #expect(favoriteCommands.compactMap(BookmarksMenuTree.bookmarkURL) == favorites.prefix(9).map(\.url))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func addingBookmarksNeedsAWebsite(hasWebsite: Bool) {
        var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
        state.hasWebsite = hasWebsite
        #expect(MenuCommandAvailability(state: state).isEnabled(.addBookmark) == hasWebsite)
        #expect(MenuCommandAvailability(state: state).isEnabled(.addFavorite) == hasWebsite)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func menuBookmarksReadFoldersWithoutACap() throws {
        let database = try makeBookmarksDatabase()
        defer { try? database.tearDown(deleteStores: true) }
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        BasicBookmarksStructure.populateDB(context: context)
        let bookmarks = MainMenuBookmarks(database: database, appSettings: AppSettingsMock(), notificationCenter: NotificationCenter())
        let folderID = try #require(bookmarks.children().compactMap { entry -> String? in
            if case .folder(_, let id) = entry { return id }
            return nil
        }.first)
        let folderRequest = BookmarkEntity.fetchRequest()
        folderRequest.predicate = NSPredicate(format: "uuid == %@", folderID)
        let folder = try #require(context.fetch(folderRequest).first)
        _ = BasicBookmarksStructure.createBookmarksList(usingNames: (1...40).map { "Extra\($0)" }, parent: folder, in: context)
        try context.save()
        #expect(bookmarks.children(ofFolderWithID: folderID).count == BasicBookmarksStructure.nestedTitles.count + 40)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bookmarkSavesAndDisplayModeChangesRebuildAndRefreshFavorites() async throws {
        let database = try makeBookmarksDatabase()
        defer { try? database.tearDown(deleteStores: true) }
        let mainContext = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        BasicBookmarksStructure.populateDB(context: mainContext)
        let notifications = NotificationCenter()
        let settings = AppSettingsMock()
        settings.favoritesDisplayMode = .displayNative(.mobile)
        let bookmarks = MainMenuBookmarks(database: database, appSettings: settings, notificationCenter: notifications)
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        var rebuildCount = 0
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        let service = MainMenuService(featureFlagger: flagger, idiom: .pad, contextProvider: { .init(favorites: bookmarks.favorites) },
                                      rebuildTriggers: [bookmarks.changes], notificationCenter: notifications, rebuildDelay: .milliseconds(1)) {
            rebuildCount += 1
            continuation.yield(())
        }
        #expect(bookmarks.favorites.count == BasicBookmarksStructure.favoriteTitles.count)

        notifications.post(name: NSManagedObjectContext.didSaveObjectsNotification,
                           object: NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType))
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 0)

        let syncContext = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        await syncContext.perform {
            notifications.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: syncContext)
        }
        _ = await iterator.next()
        #expect(rebuildCount == 1)

        settings.favoritesDisplayMode = .displayNative(.desktop)
        notifications.post(name: AppUserDefaults.Notifications.favoritesDisplayModeChange, object: nil)
        _ = await iterator.next()
        #expect(rebuildCount == 2)
        #expect(service.spec.allItems.filter { $0.command == .openBookmark }.isEmpty)
    }

    private func makeFavorites(count: Int) -> [MainMenuBookmark] {
        (1...count).compactMap { index in
            URL(string: "https://example.com/\(index)").map { MainMenuBookmark(id: "favorite-\(index)", title: "Favorite \(index)", url: $0) }
        }
    }

    private func makeBookmarksDatabase() throws -> CoreDataDatabase {
        let model = try #require(CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel"))
        let database = CoreDataDatabase(name: "MainMenuBookmarks", containerLocation: tempDBDir(), model: model)
        database.loadStore()
        return database
    }

    private func registersInMenuBar(enabled: Bool, idiom: UIUserInterfaceIdiom) -> Bool {
        guard enabled, idiom == .pad, #available(iOS 26.0, *) else { return false }
        return true
    }
}

@MainActor
private final class MainMenuBuilderSpy: NSObject, UIMenuBuilder {
    let system: UIMenuSystem = .main
    var insertedMenus: [(menu: UIMenu, before: UIMenu.Identifier)] = []

    func replaceChildren(ofMenu parentIdentifier: UIMenu.Identifier, from childrenBlock: ([UIMenuElement]) -> [UIMenuElement]) {}
    func remove(menu removedIdentifier: UIMenu.Identifier) {}
    func menu(for identifier: UIMenu.Identifier) -> UIMenu? { nil }
    func action(for identifier: UIAction.Identifier) -> UIAction? { nil }
    // swiftlint:disable:next identifier_name
    func __command(forAction action: Selector, propertyList: Any?) -> UICommand? { nil }
    func replace(menu replacedIdentifier: UIMenu.Identifier, with replacementMenu: UIMenu) {}
    func insertSibling(_ siblingMenu: UIMenu, beforeMenu siblingIdentifier: UIMenu.Identifier) {
        insertedMenus.append((siblingMenu, siblingIdentifier))
    }
    func insertSibling(_ siblingMenu: UIMenu, afterMenu siblingIdentifier: UIMenu.Identifier) {}
    func insertChild(_ childMenu: UIMenu, atStartOfMenu parentIdentifier: UIMenu.Identifier) {}
    func insertChild(_ childMenu: UIMenu, atEndOfMenu parentIdentifier: UIMenu.Identifier) {}

    @available(iOS 26.0, *)
    func replace(menu replacedIdentifier: UIMenu.Identifier, with replacementElements: [UIMenuElement]) {}
    @available(iOS 26.0, *)
    func replace(action replacedIdentifier: UIAction.Identifier, with replacementElements: [UIMenuElement]) {}
    @available(iOS 26.0, *)
    // swiftlint:disable:next identifier_name
    func __replaceCommand(forAction action: Selector, propertyList: Any?, with elements: [UIMenuElement]) {}
    @available(iOS 26.0, *)
    func insertElements(_ elements: [UIMenuElement], beforeMenu identifier: UIMenu.Identifier) {}
    @available(iOS 26.0, *)
    func insertElements(_ elements: [UIMenuElement], afterMenu identifier: UIMenu.Identifier) {}
    @available(iOS 26.0, *)
    func insertElements(_ elements: [UIMenuElement], beforeAction identifier: UIAction.Identifier) {}
    @available(iOS 26.0, *)
    func insertElements(_ elements: [UIMenuElement], afterAction identifier: UIAction.Identifier) {}
    @available(iOS 26.0, *)
    // swiftlint:disable:next identifier_name
    func __insert(_ elements: [UIMenuElement], beforeCommandForAction action: Selector, propertyList: Any?) {}
    @available(iOS 26.0, *)
    // swiftlint:disable:next identifier_name
    func __insert(_ elements: [UIMenuElement], afterCommandForAction action: Selector, propertyList: Any?) {}
    @available(iOS 26.0, *)
    func insertElements(_ elements: [UIMenuElement], atStartOfMenu identifier: UIMenu.Identifier) {}
    @available(iOS 26.0, *)
    func insertElements(_ elements: [UIMenuElement], atEndOfMenu identifier: UIMenu.Identifier) {}
    @available(iOS 26.0, *)
    func remove(action identifier: UIAction.Identifier) {}
    @available(iOS 26.0, *)
    // swiftlint:disable:next identifier_name
    func __removeCommand(forAction action: Selector, propertyList: Any?) {}
}
