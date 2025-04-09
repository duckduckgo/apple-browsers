//
//  LinkOpenBehaviorTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import CoreGraphics
import Foundation
import Testing

@testable import DuckDuckGo_Privacy_Browser

final class LinkOpenBehaviorTests {

    // MARK: - No modifiers

    // Arguments for left mouse/key press with no modifiers
    static let noModifiersArgs: [(switchToTabPref: Bool, canOpenInCurrent: Bool, shouldSelect: Bool, expectation: LinkOpenBehavior, line: UInt)] = [
        // When can open in current tab: should open in current tab
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: false, .currentTab, #line),
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: true, .currentTab, #line),
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: false, .currentTab, #line),
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: true, .currentTab, #line),

        // When cannot open in current tab, Switch to new tab preference is Off: should open in background tab
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: false, .newTab(selected: false), #line),

        // When cannot open in current tab, Switch to new tab preference is On: should open in new selected tab
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: false, .newTab(selected: true), #line),

        // When cannot open in current tab, shouldSelect is `true` (web view requested a new tab): should open in new selected tab
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: true, .newTab(selected: true), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: true, .newTab(selected: true), #line),
    ]

    @Test("Link open with no modifiers", arguments: noModifiersArgs)
    func testNoModifiers(switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool, shouldSelectNewTab: Bool, expectation: LinkOpenBehavior, line: UInt) throws {
        let events: [NSEvent] = [
            .mouseEvent(.leftMouseDown),
            .mouseEvent(.leftMouseUp),
            .mouseEvent(.leftMouseUp, modifierFlags: .capsLock),
            .mouseEvent(.leftMouseUp, modifierFlags: [.capsLock, .function]),
            .mouseEvent(.leftMouseUp, modifierFlags: .function),
            .mouseEvent(.leftMouseUp, modifierFlags: [.function, .weirdDeviceFlag]),
            .mouseEvent(.rightMouseDown),
            .mouseEvent(.rightMouseUp),
            .keyEvent(.keyDown, keyCode: 49), // spacebar
            .keyEvent(.keyUp, keyCode: 36), // return/enter
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: .capsLock),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.capsLock, .function]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: .function),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.function, .weirdDeviceFlag]),
        ]
        for event in events {
            let behavior = LinkOpenBehavior(event: event,
                                            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference,
                                            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
                                            shouldSelectNewTab: shouldSelectNewTab)

            #expect(behavior == expectation, "\(event.testDescr): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))

            // test overload with button
            let button = event.button
            let behavior2 = LinkOpenBehavior(button: button, modifierFlags: event.modifierFlags, switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference, canOpenLinkInCurrentTab: canOpenLinkInCurrentTab, shouldSelectNewTab: shouldSelectNewTab)
            #expect(behavior2 == expectation, "\(event.modifierFlags.testDescr):\(button): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        }
    }

    @Test("nil event uses default behavior", arguments: noModifiersArgs)
    func testEventIsNil(switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool, shouldSelectNewTab: Bool, expectation: LinkOpenBehavior, line: UInt) throws {
        let behavior = LinkOpenBehavior(event: nil, switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference, canOpenLinkInCurrentTab: canOpenLinkInCurrentTab, shouldSelectNewTab: shouldSelectNewTab)
        #expect(behavior == expectation,
                sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
    }

    // MARK: - Command modifier only

    static let commandModifierArgs: [(switchToTabPref: Bool, canOpenInCurrent: Bool, shouldSelect: Bool, expectation: LinkOpenBehavior, line: UInt)] = [
        // With ⌘ pressed, opens in background tab when switchToTabPref is false
        // shouldSelect (when web view opens a new tab) is ignored when ⌘ is pressed
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: false, .newTab(selected: false), #line),
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: true, .newTab(selected: false), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: false, .newTab(selected: false), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: true, .newTab(selected: false), #line),

        // With ⌘ pressed, opens in foreground tab when switchToTabPref is true
        // shouldSelect (when web view opens a new tab) is ignored when ⌘ is pressed
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: false, .newTab(selected: true), #line),
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: true, .newTab(selected: true), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: false, .newTab(selected: true), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: true, .newTab(selected: true), #line),
    ]

    @Test("Link open with ⌘", arguments: commandModifierArgs)
    func testCommandPressed(switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool, shouldSelectNewTab: Bool, expectation: LinkOpenBehavior, line: UInt) throws {
        let events: [NSEvent] = [
            .mouseEvent(.leftMouseDown, modifierFlags: [.command]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .capsLock]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .function]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .weirdDeviceFlag]),
            .mouseEvent(.rightMouseDown, modifierFlags: [.command]),
            .mouseEvent(.rightMouseUp, modifierFlags: [.command]),
            .keyEvent(.keyDown, keyCode: 49, modifierFlags: [.command]), // spacebar
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command]), // return/enter
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .capsLock]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .function]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .function, .weirdDeviceFlag]),

            .mouseEvent(.otherMouseDown, modifierFlags: []), // middle click is the equivalent of ⌘-click
            .mouseEvent(.otherMouseDown, modifierFlags: [.command]), // ⌘+middle click
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .capsLock]),
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .function]),
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .function, .weirdDeviceFlag]),
        ]
        for event in events {
            let behavior = LinkOpenBehavior(event: event,
                                            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference,
                                            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
                                            shouldSelectNewTab: shouldSelectNewTab)

            #expect(behavior == expectation, "\(event.testDescr): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))

            // test overload with button
            let button = event.button
            let behavior2 = LinkOpenBehavior(button: button, modifierFlags: event.modifierFlags, switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference, canOpenLinkInCurrentTab: canOpenLinkInCurrentTab, shouldSelectNewTab: shouldSelectNewTab)
            #expect(behavior2 == expectation, "\(event.modifierFlags.testDescr):\(button): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        }
    }

    // MARK: - Command + Shift modifiers

    static let commandShiftModifierArgs: [(switchToTabPref: Bool, canOpenInCurrent: Bool, shouldSelect: Bool, expectation: LinkOpenBehavior, line: UInt)] = [
        // With ⌘⇧ pressed, opens *selected* tab when switchToTabPref is false (⇧ inverts switchToTabPref value)
        // shouldSelect (when web view opens a new tab) is ignored when ⌘ is pressed
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: false, .newTab(selected: true), #line),
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: true, .newTab(selected: true), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: false, .newTab(selected: true), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: true, .newTab(selected: true), #line),

        // With ⌘⇧ pressed, opens *background* tab when switchToTabPref is true (⇧ inverts switchToTabPref value)
        // shouldSelect (when web view opens a new tab) is ignored when ⌘ is pressed
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: false, .newTab(selected: false), #line),
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: true, .newTab(selected: false), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: false, .newTab(selected: false), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: true, .newTab(selected: false), #line),
    ]

    @Test("Link open with ⌘⇧", arguments: commandShiftModifierArgs)
    func testCommandShiftPressed(switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool, shouldSelectNewTab: Bool, expectation: LinkOpenBehavior, line: UInt) throws {
        let events: [NSEvent] = [
            .mouseEvent(.leftMouseDown, modifierFlags: [.command, .shift]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .shift]),
            .mouseEvent(.rightMouseDown, modifierFlags: [.command, .shift]),
            .mouseEvent(.rightMouseUp, modifierFlags: [.command, .shift]),
            .mouseEvent(.rightMouseUp, modifierFlags: [.command, .shift, .capsLock]),
            .mouseEvent(.rightMouseUp, modifierFlags: [.command, .shift, .function]),
            .mouseEvent(.rightMouseUp, modifierFlags: [.command, .shift, .weirdDeviceFlag]),
            .keyEvent(.keyDown, keyCode: 49, modifierFlags: [.command, .shift]), // spacebar
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift]), // return/enter
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift, .capsLock]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift, .function]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift, .weirdDeviceFlag]),

            .mouseEvent(.otherMouseDown, modifierFlags: [.shift]), // middle click is the equivalent of ⌘-click
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .shift]), // ⇧⌘+middle click
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .shift, .capsLock]),
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .shift, .function]),
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .shift, .function, .weirdDeviceFlag]),
        ]
        for event in events {
            let behavior = LinkOpenBehavior(event: event,
                                            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference,
                                            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
                                            shouldSelectNewTab: shouldSelectNewTab)

            #expect(behavior == expectation, "\(event.testDescr): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))

            // test overload with button
            let button = event.button
            let behavior2 = LinkOpenBehavior(button: button, modifierFlags: event.modifierFlags, switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference, canOpenLinkInCurrentTab: canOpenLinkInCurrentTab, shouldSelectNewTab: shouldSelectNewTab)
            #expect(behavior2 == expectation, "\(event.modifierFlags.testDescr):\(button): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        }
    }

    // MARK: - Command + Option modifiers

    static let commandOptionModifierArgs: [(switchToTabPref: Bool, canOpenInCurrent: Bool, shouldSelect: Bool, expectation: LinkOpenBehavior, line: UInt)] = [
        // With ⌥⌘ pressed, opens background window when switchToTabPref is false
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: false, .newWindow(selected: false), #line),
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: true, .newWindow(selected: false), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: false, .newWindow(selected: false), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: true, .newWindow(selected: false), #line),

        // With ⌥⌘ pressed, opens active window when switchToTabPref is true
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: false, .newWindow(selected: true), #line),
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: true, .newWindow(selected: true), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: false, .newWindow(selected: true), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: true, .newWindow(selected: true), #line),
    ]

    @Test("Link open with ⌥⌘", arguments: commandOptionModifierArgs)
    func testCommandOptionPressed(switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool, shouldSelectNewTab: Bool, expectation: LinkOpenBehavior, line: UInt) throws {
        let events: [NSEvent] = [
            .mouseEvent(.leftMouseDown, modifierFlags: [.command, .option]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .option]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .option, .capsLock]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .option, .capsLock, .weirdDeviceFlag]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .option, .function]),
            .mouseEvent(.rightMouseDown, modifierFlags: [.command, .option]),
            .mouseEvent(.rightMouseUp, modifierFlags: [.command, .option]),
            .keyEvent(.keyDown, keyCode: 49, modifierFlags: [.command, .option]), // spacebar
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .option]), // return/enter
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .option, .capsLock]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .option, .function]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .option, .weirdDeviceFlag]),

            .mouseEvent(.otherMouseDown, modifierFlags: [.option]), // middle click is the equivalent of ⌘-click
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .option]), // ⌥⌘+middle click
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .option, .capsLock]),
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .option, .function]),
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .option, .weirdDeviceFlag]),
        ]
        for event in events {
            let behavior = LinkOpenBehavior(event: event,
                                            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference,
                                            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
                                            shouldSelectNewTab: shouldSelectNewTab)

            #expect(behavior == expectation, "\(event.testDescr): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))

            // test overload with button
            let button = event.button
            let behavior2 = LinkOpenBehavior(button: button, modifierFlags: event.modifierFlags, switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference, canOpenLinkInCurrentTab: canOpenLinkInCurrentTab, shouldSelectNewTab: shouldSelectNewTab)
            #expect(behavior2 == expectation, "\(event.modifierFlags.testDescr):\(button): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        }
    }

    // MARK: - Command + Shift + Option modifiers

    static let commandShiftOptionModifierArgs: [(switchToTabPref: Bool, canOpenInCurrent: Bool, shouldSelect: Bool, expectation: LinkOpenBehavior, line: UInt)] = [
        // With ⌘⇧⌥ pressed, opens active window when switchToTabPref is false
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: false, .newWindow(selected: true), #line),
        (switchToTabPref: false, canOpenInCurrent: true, shouldSelect: true, .newWindow(selected: true), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: false, .newWindow(selected: true), #line),
        (switchToTabPref: false, canOpenInCurrent: false, shouldSelect: true, .newWindow(selected: true), #line),

        // With ⌘⇧⌥ pressed, opens background window when switchToTabPref is true
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: false, .newWindow(selected: false), #line),
        (switchToTabPref: true, canOpenInCurrent: true, shouldSelect: true, .newWindow(selected: false), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: false, .newWindow(selected: false), #line),
        (switchToTabPref: true, canOpenInCurrent: false, shouldSelect: true, .newWindow(selected: false), #line),
    ]

    @Test("Link open with ⌘⇧⌥", arguments: commandShiftOptionModifierArgs)
    func testCommandShiftOptionPressed(switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool, shouldSelectNewTab: Bool, expectation: LinkOpenBehavior, line: UInt) throws {
        let events: [NSEvent] = [
            .mouseEvent(.leftMouseDown, modifierFlags: [.command, .shift, .option]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .shift, .option]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .shift, .option, .capsLock]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .shift, .option, .function]),
            .mouseEvent(.leftMouseUp, modifierFlags: [.command, .shift, .option, .function, .weirdDeviceFlag]),
            .mouseEvent(.rightMouseDown, modifierFlags: [.command, .shift, .option]),
            .mouseEvent(.rightMouseUp, modifierFlags: [.command, .shift, .option]),
            .keyEvent(.keyDown, keyCode: 49, modifierFlags: [.command, .shift, .option]), // spacebar
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift, .option]), // return/enter
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift, .option, .capsLock]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift, .option, .function]),
            .keyEvent(.keyUp, keyCode: 36, modifierFlags: [.command, .shift, .option, .capsLock, .function, .weirdDeviceFlag]),

            .mouseEvent(.otherMouseDown, modifierFlags: [.shift, .option]), // middle click is the equivalent of ⌘-click
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .shift, .option]), // ⌥⇧⌘+middle click
            .mouseEvent(.otherMouseUp, modifierFlags: [.command, .shift, .option, .capsLock]),
            .mouseEvent(.otherMouseUp, modifierFlags: [.command, .shift, .option, .function]),
            .mouseEvent(.otherMouseDown, modifierFlags: [.command, .shift, .option, .capsLock, .function, .weirdDeviceFlag]),
        ]
        for event in events {
            let behavior = LinkOpenBehavior(event: event,
                                            switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference,
                                            canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
                                            shouldSelectNewTab: shouldSelectNewTab)

            #expect(behavior == expectation, "\(event.testDescr): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))

            // test overload with button
            let button = event.button
            let behavior2 = LinkOpenBehavior(button: button, modifierFlags: event.modifierFlags, switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference, canOpenLinkInCurrentTab: canOpenLinkInCurrentTab, shouldSelectNewTab: shouldSelectNewTab)
            #expect(behavior2 == expectation, "\(event.modifierFlags.testDescr):\(button): switchToTabPref: \(switchToNewTabWhenOpenedPreference), canOpenInCurrent: \(canOpenLinkInCurrentTab), shouldSelect: \(shouldSelectNewTab)",
                    sourceLocation: .init(fileID: #fileID, filePath: #filePath, line: Int(line), column: 0))
        }
    }

}
    // MARK: - Helper Methods

private extension NSEvent {

    static func mouseEvent(_ type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        var event = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: modifierFlags, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let buttonNumber = switch type {
        case .rightMouseDown, .rightMouseUp: 1
        case .otherMouseDown, .otherMouseUp: 2
        default: 0
        }
        if buttonNumber != 0 {
            let cgEvent = event.cgEvent!
            cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
            event = .init(cgEvent: cgEvent)!
        }
        return event
    }

    static func keyEvent(_ type: NSEvent.EventType, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        .keyEvent(with: type, location: .zero, modifierFlags: modifierFlags, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)!
    }

    var testDescr: String {
        "\(modifierFlags.testDescr) \(typeDescr)"
    }

    var typeDescr: String {
        switch type {
        case .keyUp: return "KeyUp – \(keyCode)"
        case .keyDown: return "KeyDown – \(keyCode)"
        case .leftMouseDown: return "LeftMouseDown"
        case .leftMouseUp: return "LeftMouseUp"
        case .rightMouseDown: return "RightMouseDown"
        case .rightMouseUp: return "RightMouseUp"
        case .otherMouseDown: return "MiddleMouseDown"
        case .otherMouseUp: return "MiddleMouseUp"
        default: fatalError("Unexpected type: \(type)")
        }
    }

}

private extension NSEvent.ModifierFlags {
    static let weirdDeviceFlag = Self(rawValue: 0x010000) // outside 16-bit mask

    var testDescr: String {
        var flags = [String]()

        if contains(.capsLock)        { flags.append("⇪") }
        if contains(.function)        { flags.append("🌐") }
        if contains(.numericPad)      { flags.append("🔢") }
        if contains(.weirdDeviceFlag) { flags.append("👽") }
        if contains(.control)         { flags.append("⌃") }
        if contains(.option)          { flags.append("⌥") }
        if contains(.shift)           { flags.append("⇧") }
        if contains(.command)         { flags.append("⌘") }

        // Compute the raw value for known flags to subtract from total
        let knownFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .capsLock, .function, .numericPad]
        let unknownBits = rawValue & ~knownFlags.rawValue

        if unknownBits != 0 {
            flags.append(String(format: "0x%08X", unknownBits))
        }

        return flags.joined()
    }
}
