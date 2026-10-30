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
        if enabled && idiom == .pad {
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
        #expect(spec.removedMenus == (enabled && idiom == .pad ? [.format] : []))
        #expect(spec.mainMenus.map(\.identifier) == (enabled && idiom == .pad ? spec.menus.map(\.identifier) : [.preferences]))
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
        #expect(shared.count == (enabled && idiom == .pad ? 0 : 1))
        let sharedItems = enabled && idiom == .pad ? [] : spec.shortcutItems.filter { !enabled || availability.isEnabled($0.command) }
        #expect(commands.count == sharedItems.count + 2)
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
    func iPhoneDoesNotRebuildWhenIPadFlagChanges() async throws {
        let flagger = MockFeatureFlagger()
        var rebuildCount = 0
        let controller = MainMenuController(featureFlagger: flagger, idiom: .phone,
                                            rebuildDelay: .milliseconds(1)) { rebuildCount += 1 }
        #expect(controller.spec.shortcutRegistration == .legacy)
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        flagger.triggerUpdate()
        controller.requestRebuild()
        try await Task.sleep(for: .milliseconds(30))
        #expect(rebuildCount == 0)
        #expect(controller.spec.removedMenus.isEmpty)
        #expect(controller.spec.shortcutRegistration == .responder)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func settingsRetainsItsActionAndShortcut() throws {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad)
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
    @Test(.timeLimit(.minutes(1)))
    func unknownSelectorsAreNotMenuCommands() {
        #expect(MainMenuCommand(action: #selector(MainViewController.keyboardSettings)) == .settings)
        #expect(MainMenuCommand(action: #selector(MainViewController.keyboardEscape)) == nil)
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
        #expect(spec.menus.first { $0.identifier == .help }?.allItems.filter { $0.command == .selectTab }.count == 9)
        #expect(spec.allItems.filter { [.openLink, .openBackgroundLink].contains($0.command) }.allSatisfy { $0.shortcut == nil })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func builtStaticMenuCommandsHaveUniqueUIKitIdentities() {
        let spec = MainMenuSpec(isEnabled: true, idiom: .pad, context: .init(voiceSearchEnabled: true, fireModeEnabled: true))
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
    @Test(.timeLimit(.minutes(1)), arguments: [0, 1, 5, 9, 12])
    func builtTabCommandsPreserveSelectionInput(count: Int) throws {
        let items = MainMenuSpec(isEnabled: true, idiom: .pad).allItems.filter { $0.command == .selectTab }
        let commands = try items.map { try #require(MainMenuBuilder().makeCommand(for: $0) as? UIKeyCommand) }
        #expect(commands.map(\.input) == (1...9).map { String($0) })
        for (number, command) in zip(1...9, commands) {
            #expect(command.action == #selector(MainViewController.keyboardSelectTab(_:)))
            #expect(command.modifierFlags == .command)
            let input = try #require(command.input.flatMap(Int.init))
            let expected = count == 0 ? nil : number == 9 ? count - 1 : number <= count ? number - 1 : nil
            #expect(MainMenuSpec.tabIndex(number: input, count: count, menuEnabled: true) == expected)
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
    @Test(.timeLimit(.minutes(1)))
    func menuAlternatesStayUsableWithoutAppearingInAutomaticShortcutMenus() throws {
        let newTab = UIKeyCommand(title: "", action: MainMenuCommand.newTab.action, input: "n", modifierFlags: .command,
                                  discoverabilityTitle: UserText.keyCommandNewTab)
        let zoom = UIKeyCommand(title: "", action: MainMenuCommand.zoomIn.action, input: "=", modifierFlags: .command,
                                discoverabilityTitle: UserText.keyCommandZoomIn)
        let escape = UIKeyCommand(title: "", action: #selector(MainViewController.keyboardEscape),
                                  input: UIKeyCommand.inputEscape, modifierFlags: [])
        let commands = [newTab, zoom, escape]
        for enabled in [false, true, false] {
            let spec = MainMenuSpec(isEnabled: enabled, idiom: .pad)
            let remaining = spec.remainingKeyCommands(from: commands)
            #expect(remaining.count == commands.count)
            for (original, result) in zip(commands, remaining) {
                #expect(result.input == original.input)
                #expect(result.modifierFlags == original.modifierFlags)
                #expect(result.action == original.action)
                #expect(result.attributes.contains(.hidden) == (enabled && original !== escape))
                #expect(!result.attributes.contains(.disabled))
                #expect(!original.attributes.contains(.hidden))
            }
            if enabled {
                let visibleZoom = try #require(spec.allItems.first { $0.command == .zoomIn })
                #expect(visibleZoom.shortcut == .init(input: "+", modifiers: .command))
                let help = try #require(spec.menus.first { $0.identifier == .help })
                #expect(help.submenus.filter { $0.title == UserText.menuMoreShortcuts }.count == 1)
            }
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

}
