//
//  PromptBarShortcutTests.swift
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

import Carbon.HIToolbox
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromptBarShortcutTests: XCTestCase {

    func testWhenEncodedAndDecodedThenShortcutRoundTrips() throws {
        let shortcut = PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option])

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(PromptBarShortcut.self, from: data)

        XCTAssertEqual(decoded, shortcut)
    }

    func testWhenInitializedThenNonShortcutModifierFlagsAreDropped() {
        let shortcut = PromptBarShortcut(keyCode: UInt16(kVK_Space),
                                         modifierFlags: [.option, .capsLock, .function, .numericPad])

        XCTAssertEqual(shortcut.modifierFlags, .option)
    }

    func testWhenShortcutHasCommandOptionOrControlThenRequiredModifiersArePresent() {
        XCTAssertTrue(PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .option).hasRequiredModifiers)
        XCTAssertTrue(PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .command).hasRequiredModifiers)
        XCTAssertTrue(PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .control).hasRequiredModifiers)
    }

    func testWhenShortcutHasOnlyShiftOrNoModifiersThenRequiredModifiersAreMissing() {
        XCTAssertFalse(PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .shift).hasRequiredModifiers)
        XCTAssertFalse(PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: []).hasRequiredModifiers)
    }

    func testWhenShortcutIsReservedBySystemThenOwnerNameIsReturned() {
        let spotlight = PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .command)

        XCTAssertEqual(spotlight.reservedSystemOwnerName, "Spotlight")
    }

    func testWhenShortcutIsNotReservedThenOwnerNameIsNil() {
        XCTAssertNil(PromptBarShortcut.defaultShortcut.reservedSystemOwnerName)
        XCTAssertNil(PromptBarShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.control, .option]).reservedSystemOwnerName)
    }

    func testWhenDefaultShortcutThenItIsOptionSpace() {
        XCTAssertEqual(PromptBarShortcut.defaultShortcut.keyCode, UInt16(kVK_Space))
        XCTAssertEqual(PromptBarShortcut.defaultShortcut.modifierFlags, .option)
    }

    func testWhenAllModifiersPresentThenSymbolsFollowCanonicalOrder() {
        let shortcut = PromptBarShortcut(keyCode: UInt16(kVK_Space),
                                         modifierFlags: [.command, .shift, .option, .control])

        XCTAssertEqual(shortcut.modifierSymbols, ["⌃", "⌥", "⇧", "⌘"])
    }

    func testWhenKeyCodeIsSpaceThenDisplayStringCombinesModifiersAndKeyName() {
        let shortcut = PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .command)

        XCTAssertEqual(shortcut.displayString, "⌘" + UserText.promptBarShortcutSpaceKey)
    }

    func testWhenKeyCodeIsFunctionKeyThenDisplayStringUsesFunctionKeyName() {
        let shortcut = PromptBarShortcut(keyCode: UInt16(kVK_F5), modifierFlags: .option)

        XCTAssertEqual(shortcut.keyDisplayString, "F5")
    }
}
