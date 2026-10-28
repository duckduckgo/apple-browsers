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
        #expect(command.title == UserText.settingsTitle)
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
            #expect(padSpec.remainingKeyCommands(from: commands) == (enabled ? [alternate, fire] : commands))
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
        #expect(MainMenuCommand(action: #selector(MainViewController.keyboardReload)) == nil)
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
