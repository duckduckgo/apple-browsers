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

import FeatureFlags_iOS
import Bookmarks
import Core
import CoreData
import Persistence
import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
struct MainMenuTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func settingsRetainsItsActionAndShortcut() throws {
        let spec = MainMenuSpec(isEnabled: true)
        let menu = try #require(spec.menus.first)
        #expect(menu.identifier == .preferences)
        #expect(menu.items.count == 1)
        let command = try #require(MainMenuBuilder().makeCommand(for: menu.items[0]) as? UIKeyCommand)
        #expect(command.title == UserText.menuSettings)
        #expect(command.action == #selector(MainViewController.keyboardSettings))
        #expect(command.input == ",")
        #expect(command.modifierFlags == .command)
        #expect(command.wantsPriorityOverSystemBehavior)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func builderAppliesSettingsAndRemovesFormatOnlyWhenEnabled(enabled: Bool) throws {
        let builder = MainMenuBuilderSpy()
        MainMenuBuilder().build(MainMenuSpec(isEnabled: enabled), with: builder)
        let settings = try #require(builder.children[.preferences]?.first as? UIKeyCommand)
        #expect(settings.action == #selector(MainViewController.keyboardSettings))
        #expect(settings.input == ",")
        #expect(builder.removedMenus == (enabled ? [.format] : []))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func contextMenuSystemIsNotModified() {
        let builder = MainMenuBuilderSpy(system: .context)
        MainMenuBuilder().build(MainMenuSpec(isEnabled: true), with: builder)
        #expect(builder.children.isEmpty)
        #expect(builder.removedMenus.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func settingsShortcutMovesToMenuOnlyWhileEnabledOnIPad() {
        let flagger = MockFeatureFlagger()
        let settings = UIKeyCommand(title: "Settings", action: #selector(MainViewController.keyboardSettings),
                                    input: ",", modifierFlags: .command)
        let alternate = UIKeyCommand(title: "Settings alternate", action: #selector(MainViewController.keyboardSettings),
                                     input: ",", modifierFlags: [.command, .shift])
        let fire = UIKeyCommand(title: "Fire", action: #selector(MainViewController.keyboardFire),
                               input: UIKeyCommand.inputBackspace, modifierFlags: [.control, .alternate])
        let commands = [settings, alternate, fire]
        for enabled in [false, true, false] {
            flagger.enabledFeatureFlags = enabled ? [.ipadMenuBar] : []
            let padSpec = MainMenuSpec(isEnabled: flagger.isIPadMenuBarEnabled(idiom: .pad))
            #expect(padSpec.remainingKeyCommands(from: commands) == (enabled ? [alternate] : commands))
            #expect(padSpec.removedMenus == (enabled ? [.format] : []))
            let phoneSpec = MainMenuSpec(isEnabled: flagger.isIPadMenuBarEnabled(idiom: .phone))
            #expect(phoneSpec.remainingKeyCommands(from: commands) == commands)
            #expect(phoneSpec.removedMenus.isEmpty)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true],
          [MenuCommandAvailability.State.Presentation.browser, .tabSwitcher, .blockingModal])
    func settingsAvailabilityMatchesPresenter(shortcutsEnabled: Bool,
                                              presentation: MenuCommandAvailability.State.Presentation) {
        let availability = MenuCommandAvailability(state: .init(shortcutsEnabled: shortcutsEnabled, presentation: presentation))
        #expect(availability.isEnabled(.settings) == (shortcutsEnabled && presentation != .blockingModal))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unknownSelectorsAreNotMenuCommands() {
        #expect(MainMenuCommand(action: #selector(MainViewController.keyboardSettings)) == .settings)
        #expect(MainMenuCommand(action: #selector(MainViewController.keyboardEscape)) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func flagUpdatesRebuildOffOnOffAndIgnoreUnchangedValues() async throws {
        let flagger = MockFeatureFlagger()
        var rebuildCount = 0
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        let controller = MainMenuController(featureFlagger: flagger, idiom: .pad,
                                            rebuildDelay: .milliseconds(1)) {
            rebuildCount += 1
            continuation.yield(())
        }
        #expect(controller.spec.removedMenus.isEmpty)
        for enabled in [true, false] {
            flagger.enabledFeatureFlags = enabled ? [.ipadMenuBar] : []
            flagger.triggerUpdate()
            _ = await iterator.next()
            #expect(controller.spec.removedMenus == (enabled ? [.format] : []))
        }
        #expect(rebuildCount == 2)
        flagger.triggerUpdate()
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func rebuildRequestsCoalesceAndReadTheLatestFlagState() async throws {
        let flagger = MockFeatureFlagger()
        var rebuildCount = 0
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        let controller = MainMenuController(featureFlagger: flagger, idiom: .pad,
                                            rebuildDelay: .milliseconds(10)) {
            rebuildCount += 1
            continuation.yield(())
        }
        controller.requestRebuild()
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        flagger.triggerUpdate()
        flagger.enabledFeatureFlags = []
        flagger.triggerUpdate()
        _ = await iterator.next()
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 1)
        #expect(controller.spec.removedMenus.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iPhoneDoesNotRebuildWhenIPadFlagChanges() async throws {
        let flagger = MockFeatureFlagger()
        var rebuildCount = 0
        let controller = MainMenuController(featureFlagger: flagger, idiom: .phone,
                                            rebuildDelay: .milliseconds(1)) { rebuildCount += 1 }
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        flagger.triggerUpdate()
        controller.requestRebuild()
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 0)
        #expect(controller.spec.removedMenus.isEmpty)
    }
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func optionalCommandsFollowCapabilities(voice: Bool, fire: Bool) {
        let spec = MainMenuSpec(isEnabled: true, context: .init(voiceSearchEnabled: voice, fireModeEnabled: fire))
        #expect(spec.allItems.contains { $0.command == .voiceSearch } == voice)
        #expect(spec.allItems.contains { $0.command == .newFireTab } == fire)
        let shortcuts = spec.allItems.compactMap(\.shortcut)
        for shortcut in shortcuts {
            #expect(shortcuts.filter { $0 == shortcut }.count == 1)
        }
        let prints = spec.allItems.filter { $0.command == .printPage }
        #expect(prints.count == 2)
        #expect(prints.compactMap(\.shortcut).count == 1)
        #expect(spec.menus.first { $0.identifier == .help }?.allItems.filter { $0.command == .selectTab }.count == 9)
        #expect(spec.allItems.filter { [.openLink, .openBackgroundLink].contains($0.command) }.allSatisfy { $0.shortcut == nil })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func builderPreservesSystemItemsAndReplacesFindInPlace() throws {
        let builder = MainMenuBuilderSpy()
        let undo = UICommand(title: "Undo", action: #selector(UndoManager.undo))
        let autofillAction = UICommand(title: "Passwords", action: #selector(UndoManager.undo))
        let autofill = UIMenu(title: "AutoFill", identifier: UIMenu.Identifier("system.autofill"), children: [autofillAction])
        let find = UIMenu(title: "Find", identifier: .find, children: [])
        let close = UIKeyCommand(title: "Close", action: #selector(MainViewController.keyboardCloseTab), input: "w", modifierFlags: .command)
        let minimize = UICommand(title: "Minimize", action: #selector(UndoManager.undo))
        let search = UICommand(title: "Search", action: #selector(UndoManager.undo))
        builder.children = [.edit: [undo, find, autofill], .window: [close, minimize], .help: [search]]
        MainMenuBuilder().build(MainMenuSpec(isEnabled: true), with: builder)
        let edit = try #require(builder.children[.edit])
        #expect(edit[0] === undo)
        let retainedAutofill = try #require(edit[2] as? UIMenu)
        #expect(retainedAutofill.identifier == autofill.identifier)
        #expect(retainedAutofill.title == autofill.title)
        #expect(retainedAutofill.children.count == 1)
        #expect((retainedAutofill.children.first as? UICommand)?.action == autofillAction.action)
        let findGroup = try #require(edit[1] as? UIMenu)
        #expect((findGroup.children.first as? UIKeyCommand)?.action == MainMenuCommand.find.action)
        let window = try #require(builder.children[.window])
        #expect(window[1] === minimize)
        #expect((window[0] as? UICommand)?.action == close.action)
        #expect(!(window[0] is UIKeyCommand))
        #expect(builder.children[.help]?.first === search)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func menuOwnsEquivalentsAcrossRespondersAndRetainsHiddenAlternates() {
        let make = { (action: Selector, input: String, modifiers: UIKeyModifierFlags) in
            UIKeyCommand(title: "", action: action, input: input, modifierFlags: modifiers)
        }
        let close = make(#selector(TabSwitcherViewController.keyboardCloseWindowShortcut), "w", .command)
        let newTabAlternate = make(MainMenuCommand.newTab.action, "n", .command)
        let zoomAlternate = make(MainMenuCommand.zoomIn.action, "=", .command)
        let cursor = make(MainMenuCommand.back.action, UIKeyCommand.inputLeftArrow, .command)
        let commands = [close, newTabAlternate, zoomAlternate, cursor]
        for enabled in [false, true, false] {
            let spec = MainMenuSpec(isEnabled: enabled)
            #expect(spec.remainingKeyCommands(from: commands) == (enabled ? [newTabAlternate, zoomAlternate] : commands))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 5, 9, 12])
    func commandNineSelectsLastTabOnlyInNewMode(count: Int) {
        #expect(MainMenuSpec.tabIndex(number: 9, count: count, menuEnabled: true) == (count > 0 ? count - 1 : nil))
        #expect(MainMenuSpec.tabIndex(number: 9, count: count, menuEnabled: false) == (count >= 9 ? 8 : nil))
        #expect(MainMenuSpec.tabIndex(number: 1, count: count, menuEnabled: true) == (count > 0 ? 0 : nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func availabilityTracksWebsiteLoadingFindAndModalState() {
        var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
        #expect(!MenuCommandAvailability(state: state).isEnabled(.share))
        #expect(!MenuCommandAvailability(state: state).isEnabled(.find))
        #expect(!MenuCommandAvailability(state: state).isEnabled(.stop))
        state.hasTab = true
        #expect(MenuCommandAvailability(state: state).isEnabled(.newTab))
        #expect(MenuCommandAvailability(state: state).isEnabled(.closeTab))
        #expect(MenuCommandAvailability(state: state).isEnabled(.duplicateTab))
        #expect(!MenuCommandAvailability(state: state).isEnabled(.reload))
        state.hasWebsite = true
        state.isLoading = true
        state.findActive = true
        state.tabCount = 3
        let website = MenuCommandAvailability(state: state)
        for command in [MainMenuCommand.share, .find, .findNext, .findPrevious, .stop, .reload, .printPage, .nextTab] {
            #expect(website.isEnabled(command))
        }
        state.omnibarEditing = true
        #expect(!MenuCommandAvailability(state: state).isEnabled(.findNext))
        state = .init(shortcutsEnabled: true, presentation: .downloads)
        state.passwordsEnabled = true
        let downloads = MenuCommandAvailability(state: state)
        #expect(downloads.isEnabled(.showPasswords))
        #expect(downloads.isEnabled(.showTabs))
        #expect(downloads.title(for: .showDownloads) == UserText.menuHideDownloads)
        #expect(downloads.title(for: .showPasswords) == UserText.menuShowPasswords)
        #expect(!downloads.isEnabled(.newTab))
        state = .init(shortcutsEnabled: true, presentation: .tabSwitcher)
        state.canHideTabs = false
        #expect(!MenuCommandAvailability(state: state).isEnabled(.showTabs))
        #expect(!MenuCommandAvailability(state: state).isEnabled(.closeTab))
        #expect(MenuCommandAvailability(state: state).isEnabled(.newTab))
        for command in [MainMenuCommand.showDownloads, .showPasswords, .settings, .about, .feedback] {
            #expect(!MenuCommandAvailability(state: state).isEnabled(command))
        }
        #expect(MenuCommandAvailability(state: state).title(for: .showTabs) == UserText.menuHideTabs)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: MainMenuCommand.allCases)
    func lockedAndBlockingPresentationsDisableCommands(command: MainMenuCommand) {
        #expect(!MenuCommandAvailability(state: .init(shortcutsEnabled: false, presentation: .browser)).isEnabled(command))
        #expect(!MenuCommandAvailability(state: .init(shortcutsEnabled: true, presentation: .blockingModal)).isEnabled(command))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func voiceAvailabilityRebuildsStaticCommandsAtRuntime() async {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        let notifications = NotificationCenter()
        var voiceEnabled = false
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        let controller = MainMenuController(featureFlagger: flagger, idiom: .pad,
                                            contextProvider: { .init(voiceSearchEnabled: voiceEnabled) },
                                            notificationCenter: notifications, rebuildDelay: .milliseconds(1)) { continuation.yield(()) }
        for enabled in [true, false] {
            voiceEnabled = enabled
            notifications.post(name: .speechRecognizerDidChangeAvailability, object: nil)
            _ = await iterator.next()
            #expect(controller.spec.allItems.contains { $0.command == .voiceSearch } == enabled)
        }
    }


    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bookmarksMenuOwnsShortcutsAndBuildsFavoritesStatically() throws {
        let favorites = (1...12).map { MainMenuBookmark(title: "Favorite \($0)", url: URL(string: "https://example.com/\($0)")!) }
        let spec = MainMenuSpec(isEnabled: true, context: .init(favorites: favorites))
        let builder = MainMenuBuilderSpy()
        var folderFetchCount = 0
        MainMenuBuilder(bookmarkChildren: { _ in
            folderFetchCount += 1
            return []
        }).build(spec, with: builder)
        #expect(folderFetchCount == 0)
        let insertion = try #require(builder.insertedMenus.first)
        #expect(insertion.before == .window)
        #expect(insertion.menu.title == UserText.menuBookmarks)
        let favoritesMenu = try #require(insertion.menu.children.compactMap { $0 as? UIMenu }
            .first { $0.identifier == UIMenu.Identifier("com.duckduckgo.bookmarks.favorites") })
        #expect(favoritesMenu.children.count == 12)
        let shortcuts = favoritesMenu.children.compactMap { $0 as? UIKeyCommand }
        #expect(shortcuts.map(\.input) == (1...9).map { String($0) })
        #expect(shortcuts.allSatisfy { $0.modifierFlags == [.alternate, .command] })
        #expect(shortcuts.first?.propertyList as? String == favorites.first?.url.absoluteString)
        #expect(!favoritesMenu.children.contains { $0 is UIDeferredMenuElement })
        let tree = try #require(insertion.menu.children.compactMap { $0 as? UIMenu }
            .first { $0.identifier == UIMenu.Identifier("com.duckduckgo.bookmarks.tree") })
        #expect(tree.children.first is UIDeferredMenuElement)
        for (command, input, modifiers) in [(MainMenuCommand.showBookmarks, "k", UIKeyModifierFlags([.shift, .command])),
                                            (.addBookmark, "d", .command), (.addFavorite, "d", [.control, .command])] {
            let item = try #require(spec.allItems.first { $0.command == command })
            #expect(item.shortcut == .init(input: input, modifiers: modifiers))
        }
        #expect(spec.menus.first { $0.identifier == .view }?.allItems.contains { $0.command == .showBookmarks } == false)
        #expect(MainMenuSpec(isEnabled: false, context: .init(favorites: favorites)).allItems.allSatisfy { $0.command == .settings })
        let allShortcuts = spec.allItems.compactMap(\.shortcut)
        #expect(allShortcuts.allSatisfy { shortcut in allShortcuts.filter { $0 == shortcut }.count == 1 })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bookmarksAvailabilityFollowsPageAndModalState() {
        for hasWebsite in [false, true] {
            var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
            state.hasWebsite = hasWebsite
            #expect(MenuCommandAvailability(state: state).isEnabled(.addBookmark) == hasWebsite)
            #expect(MenuCommandAvailability(state: state).isEnabled(.addFavorite) == hasWebsite)
        }
        for presentation in [MenuCommandAvailability.State.Presentation.bookmarks, .settings, .downloads, .passwords] {
            let availability = MenuCommandAvailability(state: .init(shortcutsEnabled: true, presentation: presentation))
            #expect(availability.isEnabled(.showBookmarks))
            #expect(availability.isEnabled(.importBookmarks))
            #expect(availability.isEnabled(.exportBookmarks))
            #expect(availability.isEnabled(.openBookmark))
            #expect(availability.title(for: .showBookmarks) == (presentation == .bookmarks ? UserText.menuHideBookmarks : UserText.menuShowBookmarks))
            #expect(!availability.isEnabled(.addBookmark))
        }
        var emptySwitcher = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .tabSwitcher)
        emptySwitcher.canHideTabs = false
        for command in [MainMenuCommand.showBookmarks, .importBookmarks, .exportBookmarks, .openBookmark] {
            #expect(!MenuCommandAvailability(state: emptySwitcher).isEnabled(command))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bookmarkSnapshotsReadCurrentFolderContentsWithoutACap() throws {
        let model = try #require(CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel"))
        let database = CoreDataDatabase(name: "MenuBookmarks", containerLocation: tempDBDir(), model: model)
        database.loadStore()
        defer { try? database.tearDown(deleteStores: true) }
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        BasicBookmarksStructure.populateDB(context: context)
        let settings = AppSettingsMock()
        settings.favoritesDisplayMode = .displayNative(.mobile)
        let provider = MainMenuBookmarks(database: database, appSettings: settings)
        let folder = try #require(provider.children().compactMap { entry -> String? in
            if case .folder(_, let id) = entry { return id }
            return nil
        }.first)
        #expect(provider.children(of: folder).count == 3)
        let folderRequest = BookmarkEntity.fetchRequest()
        folderRequest.predicate = NSPredicate(format: "uuid == %@", folder)
        let entity = try #require(context.fetch(folderRequest).first)
        _ = BasicBookmarksStructure.createBookmarksList(usingNames: (1...40).map { "Extra\($0)" }, parent: entity, in: context)
        try context.save()
        #expect(provider.children(of: folder).count == 43)
        #expect(provider.children().count == 4)
        #expect(provider.favorites.map(\.title) == BasicBookmarksStructure.favoriteTitles)
        settings.favoritesDisplayMode = .displayNative(.desktop)
        #expect(provider.favorites.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bookmarkSaveRebuildsForItsStoreIncludingBackgroundSyncContexts() async throws {
        let model = try #require(CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel"))
        let database = CoreDataDatabase(name: "MenuBookmarks", containerLocation: tempDBDir(), model: model)
        database.loadStore()
        defer { try? database.tearDown(deleteStores: true) }
        let notifications = NotificationCenter()
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        var rebuildCount = 0
        let controller = MainMenuController(featureFlagger: flagger, idiom: .pad, notificationCenter: notifications,
                                            bookmarksDatabase: database, rebuildDelay: .milliseconds(1)) {
            rebuildCount += 1
            continuation.yield(())
        }
        let unrelated = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        notifications.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: unrelated)
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 0)
        let local = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let sync = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        for context in [local, sync] {
            await context.perform {
                notifications.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: context)
            }
            _ = await iterator.next()
        }
        #expect(rebuildCount == 2)
        #expect(controller.spec.ownsKeyCommands)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func favoritesDisplayModeChangeRebuildsStaticFavorites() async {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        let notifications = NotificationCenter()
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        var favorites: [MainMenuBookmark] = []
        let controller = MainMenuController(featureFlagger: flagger, idiom: .pad,
                                            contextProvider: { .init(favorites: favorites) }, notificationCenter: notifications,
                                            rebuildDelay: .milliseconds(1)) { continuation.yield(()) }
        favorites = [MainMenuBookmark(title: "Changed", url: URL(string: "https://example.com")!)]
        notifications.post(name: AppUserDefaults.Notifications.favoritesDisplayModeChange, object: nil)
        _ = await iterator.next()
        #expect(controller.spec.allItems.filter { $0.command == .openBookmark }.map(\.title) == ["Changed"])
    }

}

@MainActor
private final class MainMenuBuilderSpy: NSObject, UIMenuBuilder {
    let system: UIMenuSystem
    var children: [UIMenu.Identifier: [UIMenuElement]] = [:]
    var removedMenus: [UIMenu.Identifier] = []

    init(system: UIMenuSystem? = nil) {
        self.system = system ?? .main
    }

    func replaceChildren(ofMenu parentIdentifier: UIMenu.Identifier, from childrenBlock: ([UIMenuElement]) -> [UIMenuElement]) {
        children[parentIdentifier] = childrenBlock(children[parentIdentifier] ?? [])
    }

    func remove(menu removedIdentifier: UIMenu.Identifier) {
        removedMenus.append(removedIdentifier)
    }

    func menu(for identifier: UIMenu.Identifier) -> UIMenu? { nil }
    func action(for identifier: UIAction.Identifier) -> UIAction? { nil }
    // swiftlint:disable:next identifier_name
    func __command(forAction action: Selector, propertyList: Any?) -> UICommand? { nil }
    func replace(menu replacedIdentifier: UIMenu.Identifier, with replacementMenu: UIMenu) {}
    var insertedMenus: [(menu: UIMenu, before: UIMenu.Identifier)] = []
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
