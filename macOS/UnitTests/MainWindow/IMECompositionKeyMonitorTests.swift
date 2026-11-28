//
//  IMECompositionKeyMonitorTests.swift
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

import AppKit
import Testing

@testable import DuckDuckGo_Privacy_Browser

@Suite("IME composition and the window keyDown monitor")
struct IMECompositionKeyMonitorTests {

    private static let plainModifierFlags: [NSEvent.ModifierFlags] = [
        [],
        .capsLock,
        .option,
        .shift,
        .control,
        [.control, .shift]
    ]

    private static let commandModifierFlags: [NSEvent.ModifierFlags] = [
        .command,
        [.command, .shift],
        [.command, .capsLock],
        [.command, .option]
    ]

    @Test(
        "Plain keys are left to the input method and do not query marked text",
        arguments: plainModifierFlags
    )
    func plainKeysAreLeftToTheInputMethod(modifierFlags: NSEvent.ModifierFlags) {
        #expect(mayRead(modifierFlags, hasMarkedText: { true }) == false)
        #expect(mayRead(modifierFlags, hasMarkedText: { false }) == false)
    }

    @Test("A plain key does not ask the focused editor whether text is marked")
    func plainKeyDoesNotQueryMarkedText() {
        var queried = false
        let allowed = IMECompositionKeyMonitor.mayReadCharacters(modifierFlags: []) {
            queried = true
            return true
        }
        #expect(allowed == false)
        #expect(queried == false)
    }

    @Test(
        "Command shortcuts can still read the character when nothing is composing",
        arguments: commandModifierFlags
    )
    func commandShortcutsAreInterpretedWhenNotComposing(modifierFlags: NSEvent.ModifierFlags) {
        #expect(mayRead(modifierFlags, hasMarkedText: { false }))
    }

    @Test("Command shortcuts are not interpreted while an IME composition is active")
    func commandShortcutsWaitUntilCompositionEnds() {
        #expect(mayRead(.command, hasMarkedText: { true }) == false)
        #expect(mayRead([.command, .shift], hasMarkedText: { true }) == false)
    }

    @Test("Marked text is queried only after the event is known to be a command shortcut")
    func markedTextIsQueriedOnlyForCommandShortcuts() {
        var queries = 0
        _ = IMECompositionKeyMonitor.mayReadCharacters(modifierFlags: .command) {
            queries += 1
            return false
        }
        #expect(queries == 1)
    }

    private func mayRead(_ modifierFlags: NSEvent.ModifierFlags, hasMarkedText: @escaping () -> Bool) -> Bool {
        IMECompositionKeyMonitor.mayReadCharacters(modifierFlags: modifierFlags, hasMarkedText: hasMarkedText)
    }

}
