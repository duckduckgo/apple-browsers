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
import Combine
import Core
import CoreData
import DesignResourcesKitIcons
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
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func duckAIButtonToggleFollowsButtonVisibility(isVisible: Bool) {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad)
        #expect(spec.allItems.contains { $0.command == .toggleDuckAIButton })
        var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
        #expect(!MenuCommandAvailability(state: state).isEnabled(.toggleDuckAIButton))
        state.duckAIShortcutAvailable = true
        state.duckAIButtonVisible = isVisible
        let availability = MenuCommandAvailability(state: state)
        #expect(availability.isEnabled(.toggleDuckAIButton))
        #expect(availability.title(for: .toggleDuckAIButton) == (isVisible ? UserText.menuHideDuckAIButton : UserText.menuShowDuckAIButton))
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
    @Test(.timeLimit(.minutes(1)), arguments: [UIUserInterfaceIdiom.phone, .pad])
    func onboardingHidesBrowserMenusFromMenuBar(idiom: UIUserInterfaceIdiom) {
        let onboarding = MainMenuSpec(isEnabled: true, idiom: idiom, context: .init(aiChatEnabled: true, isOnboarding: true))
        let browsing = MainMenuSpec(isEnabled: true, idiom: idiom, context: .init(aiChatEnabled: true))
        if registersInMenuBar(enabled: true, idiom: idiom) {
            #expect(onboarding.mainMenus.isEmpty)
            #expect(onboarding.removedMenus == [.format, .file, .view])
        } else {
            #expect(onboarding.mainMenus.map(\.identifier) == browsing.mainMenus.map(\.identifier))
            #expect(onboarding.removedMenus == browsing.removedMenus)
        }
        #expect(!browsing.mainMenus.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func firstValueIsNilWhenPublisherSendsNothingInTime() async {
        let silentPublisher = PassthroughSubject<Int, Error>()
        #expect(await silentPublisher.firstValue(within: .milliseconds(10)) == nil)
        withExtendedLifetime(silentPublisher) {}
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func firstValueReturnsTheFirstValueSentInTime() async {
        let publisher = [1, 2].publisher.setFailureType(to: Error.self)
        #expect(await publisher.firstValue(within: .seconds(1)) == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func firstValueIsNilWhenPublisherFails() async {
        let failingPublisher = Fail<Int, Error>(error: CancellationError())
        #expect(await failingPublisher.firstValue(within: .seconds(1)) == nil)
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
    func appItemsAppearInFileAndDuckDuckGoMenus() throws {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad)
        let fileMenu = try #require(spec.menus.first { $0.identifier == .file })
        let duckDuckGoMenu = try #require(spec.menus.first { $0.identifier == .preferences })
        let fileImport = try #require(fileMenu.submenus.first { $0.items.map(\.command) == [.importData] })
        let appSetup = try #require(duckDuckGoMenu.submenus.first)

        #expect(fileMenu.submenus.firstIndex { $0.identifier == fileImport.identifier } == 1)
        #expect(appSetup.items.map(\.command) == [.setDefaultBrowser, .addToDock, .addWidget])
        #expect(MainMenuCommand.importData.action == #selector(MainViewController.menuImportData))
        #expect(MainMenuCommand.setDefaultBrowser.action == #selector(MainViewController.menuSetDefaultBrowser))
        #expect(MainMenuCommand.addToDock.action == #selector(MainViewController.menuAddToDock))
        #expect(MainMenuCommand.addWidget.action == #selector(MainViewController.menuAddWidget))
        #expect(!MainMenuSpec(isEnabled: false, idiom: .pad).allItems.contains { $0.command == .addToDock })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func bookmarksShortcutsAreUniqueAndAddingNeedsAWebsite() {
        let favorites = makeFavorites(count: 12)
        let spec = MainMenuSpec(isEnabled: true, idiom: .phone, context: .init(favorites: favorites))
        for command in [MainMenuCommand.showBookmarks, .addBookmark, .addFavorite] {
            #expect(spec.allItems.filter { $0.command == command }.count == 1)
        }
        var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
        let favoriteCommands = MainMenuBuilder().keyCommands(for: spec, from: [], availability: MenuCommandAvailability(state: state))
            .filter { $0.action == MainMenuCommand.openBookmark.action }
        #expect(favoriteCommands.map(\.input) == (1...9).map { String($0) })
        #expect(favoriteCommands.compactMap(BookmarksMenuTree.bookmarkURL) == favorites.prefix(9).map(\.url))
        #expect(!MenuCommandAvailability(state: state).isEnabled(.addBookmark))
        state.hasWebsite = true
        #expect(MenuCommandAvailability(state: state).isEnabled(.addBookmark))
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

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func menuCommandsShowOnlyTheirDesignIcons() {
        typealias Glyphs = DesignSystemImages.Glyphs.Size16
        let expectedImages: [MainMenuCommand: UIImage] = [
            .settings: Glyphs.settings, .newTab: Glyphs.add, .newFireTab: Glyphs.fireWindow,
            .voiceSearch: Glyphs.permissionMicrophone, .share: Glyphs.shareApple, .printPage: Glyphs.print,
            .find: Glyphs.findInPage, .about: Glyphs.info, .feedback: Glyphs.feedback
        ]
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad,
                                context: .init(voiceSearchEnabled: true, fireModeEnabled: true, aiChatEnabled: true))
        for item in spec.allItems {
            #expect(MainMenuBuilder().makeCommand(for: item).image == expectedImages[item.command], "\(item.command)")
        }
        #expect(MainMenuSpec(isEnabled: false, idiom: .pad).allItems.allSatisfy { $0.image == nil })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recentChatsShowChatIconsAndDeleteAllShowsFire() throws {
        let url = try #require(URL(string: "https://duck.ai/chat/1"))
        let elements = DuckAIRecentChatsMenuContent.elements(for: .init(recentChats: [.init(title: "Chat", url: url)], totalChatCount: 1))
        let commands = elements.compactMap { $0 as? UIMenu }.flatMap(\.children).compactMap { $0 as? UICommand }
        #expect(commands.map(\.image) == [DesignSystemImages.Glyphs.Size16.chat, DesignSystemImages.Glyphs.Size16.fire])
    }

    @available(iOS 27, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func menuItemsWithImagesAskToShowThemOnIOS27() {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad,
                                context: .init(voiceSearchEnabled: true, fireModeEnabled: true, aiChatEnabled: true))
        for item in spec.allItems {
            let expected: UIMenuElement.ImageVisibility = item.image == nil ? .automatic : .visible
            #expect(MainMenuBuilder().makeCommand(for: item).preferredImageVisibility == expected, "\(item.command)")
        }
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
