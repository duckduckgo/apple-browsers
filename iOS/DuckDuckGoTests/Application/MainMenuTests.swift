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
            #expect(commands.count == 1)
            #expect(settings.action == #selector(MainViewController.keyboardSettings))
            #expect(settings.input == ",")
            #expect(settings.modifierFlags == .command)
            #expect(settings.wantsPriorityOverSystemBehavior)
        }
        #expect(spec.removedMenus == (enabled && idiom == .pad ? [.format] : []))
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
            #expect(commands.count == (shouldRegister ? 1 : 0))
            #expect(commands.allSatisfy { $0.action == #selector(MainViewController.keyboardSettings) })
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
        #expect(commands.contains { $0 === alternate })
        #expect(commands.contains { $0 === otherAction })
        let shared = commands.filter {
            $0.action == #selector(MainViewController.keyboardSettings) && $0.input == "," && $0.modifierFlags == .command
        }
        #expect(shared.count == (enabled && idiom == .pad ? 0 : 1))
        #expect(commands.count == (enabled && idiom == .pad ? 2 : 3))
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
            #expect(service.spec.removedMenus == (enabled ? [.format] : []))
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
}
