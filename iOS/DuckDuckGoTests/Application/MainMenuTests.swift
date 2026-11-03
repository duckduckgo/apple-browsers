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
    @Test(.timeLimit(.minutes(1)))
    func phoneRegistersEveryIndexedTabShortcutFromNestedMenus() {
        var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
        state.tabCount = 12
        let commands = MainMenuBuilder().keyCommands(for: MainMenuSpec(isEnabled: true, idiom: .phone), from: [],
                                                     availability: MenuCommandAvailability(state: state))
        let indexed = commands.filter { $0.action == MainMenuCommand.selectTab.action }
        #expect(indexed.map(\.input) == (1...9).map { String($0) })
        #expect(indexed.allSatisfy { $0.modifierFlags == .command })
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
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func optionalCommandsFollowCapabilities(voice: Bool, fire: Bool) {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad, context: .init(voiceSearchEnabled: voice, fireModeEnabled: fire))
        #expect(spec.allItems.contains { $0.command == .voiceSearch } == voice)
        #expect(spec.allItems.contains { $0.command == .newFireTab } == fire)
        let shortcuts = spec.allItems.compactMap(\.shortcut)
        for shortcut in shortcuts {
            #expect(shortcuts.filter { $0 == shortcut }.count == 1)
        }
        let prints = spec.allItems.filter { $0.command == .printPage }
        #expect(prints.count == 1)
        #expect(prints.compactMap(\.shortcut).count == 1)
        #expect(spec.menus.first { $0.identifier == .file }?.allItems.contains { $0.command == .printPage } == true)
        #expect(spec.menus.first { $0.identifier == .edit }?.allItems.contains { $0.command == .printPage } == false)
        #expect(spec.keyCommandItems.filter { $0.command == .selectTab }.count == 9)
        let expectedKeyCommandOnly = registersInMenuBar(enabled: true, idiom: .pad) ? spec.keyCommandItems.count : 0
        #expect(MainMenuBuilder().keyCommandOnlyCommands(for: spec).count == expectedKeyCommandOnly)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func builtStaticMenuCommandsHaveUniqueUIKitIdentities() {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad, context: .init(voiceSearchEnabled: true, fireModeEnabled: true,
                                                                             aiChatEnabled: true))
        let commands = spec.allItems.map { MainMenuBuilder().makeCommand(for: $0) }
        #expect(commands.count == spec.allItems.count)
        for (index, command) in commands.enumerated() {
            let duplicates = commands.dropFirst(index + 1).filter {
                $0.action == command.action && ($0.propertyList as? NSObject) == (command.propertyList as? NSObject)
            }
            #expect(duplicates.isEmpty, "Duplicate UIKit command identity for \(command.title): \(duplicates.map(\.title))")
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
    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 5, 9, 12])
    func commandNineSelectsLastTabOnlyInNewMode(count: Int) {
        #expect(MainMenuSpec.tabIndex(number: 9, count: count, menuEnabled: true) == (count > 0 ? count - 1 : nil))
        #expect(MainMenuSpec.tabIndex(number: 9, count: count, menuEnabled: false) == (count >= 9 ? 8 : nil))
        #expect(MainMenuSpec.tabIndex(number: 1, count: count, menuEnabled: true) == (count > 0 ? 0 : nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: MainMenuCommand.allCases)
    func lockedAndBlockingPresentationsDisableCommands(command: MainMenuCommand) {
        #expect(!MenuCommandAvailability(state: .init(shortcutsEnabled: false, presentation: .browser)).isEnabled(command))
        #expect(!MenuCommandAvailability(state: .init(shortcutsEnabled: true, presentation: .blockingModal)).isEnabled(command))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func duckAIMenuIsRemovedWhenDuckAIIsDisabled(aiChatEnabled: Bool) throws {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad, context: .init(aiChatEnabled: aiChatEnabled))
        let duckAIMenu = spec.menus.first { $0.identifier == DuckAIMenuSection.identifier }
        let duckAICommands: [MainMenuCommand] = [.openDuckAI, .newChat, .newVoiceChat, .newImageChat]
        #expect((duckAIMenu != nil) == aiChatEnabled)
        #expect(spec.allItems.contains { duckAICommands.contains($0.command) } == aiChatEnabled)
        guard aiChatEnabled else { return }
        let menu = try #require(duckAIMenu)
        #expect(menu.placement == .insert(sibling: .view, position: .after))
        #expect(menu.submenus.last?.deferredContent == DuckAIMenuSection.recentChatsIdentifier)
        let shortcuts = Dictionary(uniqueKeysWithValues: menu.allItems.compactMap { item in item.shortcut.map { (item.command, $0) } })
        #expect(shortcuts == [.newChat: .init(input: "n", modifiers: [.alternate, .command]),
                              .newVoiceChat: .init(input: "v", modifiers: [.alternate, .command]),
                              .newImageChat: .init(input: "g", modifiers: [.alternate, .command])])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recentChatsListChatsAboveDeleteAllChats() throws {
        let first = try #require(URL(string: "https://duck.ai/?chatID=1"))
        let second = try #require(URL(string: "https://duck.ai/?chatID=2"))
        let chats = DuckAIRecentChatsMenuContent.Chats(recentChats: [.init(title: "First", url: first), .init(title: "Second", url: second)],
                                                       totalChatCount: 12)
        let menus = DuckAIRecentChatsMenuContent.elements(for: chats).compactMap { $0 as? UIMenu }
        #expect(menus.count == 2)
        #expect(menus.allSatisfy { $0.options.contains(.displayInline) })
        let recentChats = try #require(menus.first)
        #expect(recentChats.title == UserText.menuRecentChats)
        let recentChatCommands = recentChats.children.compactMap { $0 as? UICommand }
        #expect(recentChatCommands.map(\.title) == ["First", "Second"])
        #expect(recentChatCommands.map(\.action) == [MainMenuCommand.openRecentChat.action, MainMenuCommand.openRecentChat.action])
        #expect(recentChatCommands.map { $0.propertyList as? String } == [first.absoluteString, second.absoluteString])
        let deleteAll = try #require(menus.last?.children.first as? UICommand)
        #expect(deleteAll.action == MainMenuCommand.deleteAllChats.action)
        #expect(deleteAll.propertyList as? String == "12")
        #expect(menus.allSatisfy { $0.children.allSatisfy { !($0 is UIKeyCommand) } })
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
    @Test(.timeLimit(.minutes(1)), arguments: [MainMenuCommand.openDuckAI, .newChat, .newVoiceChat, .newImageChat,
                                               .openRecentChat, .deleteAllChats])
    func duckAICommandsFollowDuckAISettingOnEveryPage(command: MainMenuCommand) {
        let presentations: [MenuCommandAvailability.State.Presentation] = [.browser, .tabSwitcher, .passwords, .downloads,
                                                                            .bookmarks, .settings]
        for presentation in presentations {
            for aiChatEnabled in [false, true] {
                var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: presentation)
                state.aiChatEnabled = aiChatEnabled
                #expect(MenuCommandAvailability(state: state).isEnabled(command) == aiChatEnabled)
            }
        }
        var emptySwitcher = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .tabSwitcher)
        emptySwitcher.aiChatEnabled = true
        emptySwitcher.canHideTabs = false
        #expect(!MenuCommandAvailability(state: emptySwitcher).isEnabled(command))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func duckAIShortcutsRegisterAsKeyCommandsWithoutMenuBar(aiChatEnabled: Bool) {
        let spec = MainMenuSpec(isEnabled: true, idiom: .phone, context: .init(aiChatEnabled: aiChatEnabled))
        var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: .browser)
        state.aiChatEnabled = aiChatEnabled
        let commands = MainMenuBuilder().keyCommands(for: spec, from: [], availability: MenuCommandAvailability(state: state))
        let newChat = commands.first { $0.action == MainMenuCommand.newChat.action }
        #expect((newChat != nil) == aiChatEnabled)
        #expect(newChat.map { $0.input == "n" && $0.modifierFlags == [.alternate, .command] } ?? true)
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

    private func registersInMenuBar(enabled: Bool, idiom: UIUserInterfaceIdiom) -> Bool {
        guard enabled, idiom == .pad, #available(iOS 26.0, *) else { return false }
        return true
    }
}
