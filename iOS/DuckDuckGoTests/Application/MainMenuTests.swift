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
        let spec = MainMenuSpec(isEnabled: true, context: .init(voiceSearchEnabled: true, fireModeEnabled: true))
        let builder = MainMenuBuilderSpy()
        MainMenuBuilder().build(spec, with: builder)
        func collectCommands(in elements: [UIMenuElement]) -> [UICommand] {
            elements.flatMap { element in
                if let menu = element as? UIMenu { return collectCommands(in: menu.children) }
                return (element as? UICommand).map { [$0] } ?? []
            }
        }
        let commands = collectCommands(in: builder.children.values.flatMap { $0 })
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
        let items = MainMenuSpec(isEnabled: true).allItems.filter { $0.command == .selectTab }
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
            let spec = MainMenuSpec(isEnabled: enabled)
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
    func insertSibling(_ siblingMenu: UIMenu, beforeMenu siblingIdentifier: UIMenu.Identifier) {}
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
