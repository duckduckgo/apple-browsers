//
//  AddressBarEditingTestSupport.swift
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
import XCTest

/// A key press: the key and its modifier flags.
typealias EditingKey = (key: XCUIKeyboardKey, flags: XCUIElement.KeyModifierFlags)

/// The editing / selection shortcuts exercised by the address bar and Duck.ai omnibar tests.
enum EditingKeys {
    static let left: EditingKey = (XCUIKeyboardKey.leftArrow, [])
    static let right: EditingKey = (XCUIKeyboardKey.rightArrow, [])
    static let shiftLeft: EditingKey = (XCUIKeyboardKey.leftArrow, .shift)
    static let shiftRight: EditingKey = (XCUIKeyboardKey.rightArrow, .shift)
    static let optLeft: EditingKey = (XCUIKeyboardKey.leftArrow, .option)
    static let optRight: EditingKey = (XCUIKeyboardKey.rightArrow, .option)
    static let optShiftLeft: EditingKey = (XCUIKeyboardKey.leftArrow, [.option, .shift])
    static let optShiftRight: EditingKey = (XCUIKeyboardKey.rightArrow, [.option, .shift])
    static let cmdLeft: EditingKey = (XCUIKeyboardKey.leftArrow, .command)
    static let cmdRight: EditingKey = (XCUIKeyboardKey.rightArrow, .command)
    static let cmdShiftLeft: EditingKey = (XCUIKeyboardKey.leftArrow, [.command, .shift])
    static let cmdShiftRight: EditingKey = (XCUIKeyboardKey.rightArrow, [.command, .shift])

    static let backspace: EditingKey = (XCUIKeyboardKey.delete, [])
    static let fnDelete: EditingKey = (XCUIKeyboardKey.delete, .function)
    static let optDelete: EditingKey = (XCUIKeyboardKey.delete, .option)
    static let cmdDelete: EditingKey = (XCUIKeyboardKey.delete, .command)
    static let forwardDelete: EditingKey = (XCUIKeyboardKey.forwardDelete, .function)
    static let optForwardDelete: EditingKey = (XCUIKeyboardKey.forwardDelete, .option)
    static let cmdForwardDelete: EditingKey = (XCUIKeyboardKey.forwardDelete, .command)

    static let selectAll: EditingKey = (XCUIKeyboardKey(rawValue: "a"), .command)
    static let copy: EditingKey = (XCUIKeyboardKey(rawValue: "c"), .command)
    static let undo: EditingKey = (XCUIKeyboardKey(rawValue: "z"), .command)

    static let ctrlA: EditingKey = (XCUIKeyboardKey(rawValue: "a"), .control)
    static let ctrlE: EditingKey = (XCUIKeyboardKey(rawValue: "e"), .control)
    static let ctrlK: EditingKey = (XCUIKeyboardKey(rawValue: "k"), .control)
    static let ctrlD: EditingKey = (XCUIKeyboardKey(rawValue: "d"), .control)
    static let ctrlH: EditingKey = (XCUIKeyboardKey(rawValue: "h"), .control)
}

/// Drives a text element (address bar or Duck.ai omnibar text view) with keyboard shortcuts and reads its contents back.
struct EditingDriver {

    /// Text the address bar appends after the typed text, e.g. " – Search with DuckDuckGo" or " – Visit duckduckgo.com".
    static let suffixSeparator = " – "

    /// The element receiving the key presses.
    let element: XCUIElement

    /// Set for text views that XCUI cannot read the value of: the contents are then read by selecting all and copying,
    /// which replaces the current selection.
    var readsContentByCopying = false

    /// The element the mouse coordinates are relative to, when it differs from `element`.
    var mouseTarget: XCUIElement?

    /// The element contents including any address bar suffix.
    var rawValue: String {
        guard readsContentByCopying else { return element.value as? String ?? "" }
        press(EditingKeys.selectAll)
        return selectedText() ?? ""
    }

    /// The element contents without the address bar suffix.
    var value: String {
        rawValue.components(separatedBy: Self.suffixSeparator).first ?? rawValue
    }

    func press(_ key: EditingKey, times: Int = 1) {
        for _ in 0..<times {
            element.typeKey(key.key, modifierFlags: key.flags)
        }
    }

    func press(_ keys: [EditingKey]) {
        for key in keys {
            press(key)
        }
    }

    func type(_ text: String) {
        element.typeText(text)
    }

    /// Caret to the very end of the text (before the suffix).
    func moveCaretToEnd() {
        press(EditingKeys.cmdRight)
    }

    func moveCaretToStart() {
        press(EditingKeys.cmdLeft)
    }

    /// Caret two words before the end, i.e. right before the second to last word.
    func moveCaretTwoWordsFromEnd() {
        moveCaretToEnd()
        press(EditingKeys.optLeft, times: 2)
    }

    /// Returns exactly what the current selection contains, by copying it. Returns `nil` when nothing is selected.
    /// The previous pasteboard contents are restored afterwards.
    func selectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = Self.snapshot(of: pasteboard)
        defer { Self.restore(savedItems, to: pasteboard) }

        let sentinel = "no-selection-\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)
        press(EditingKeys.copy)
        let copied = pasteboard.string(forType: .string)
        return copied == sentinel ? nil : copied
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        let items = pasteboard.pasteboardItems ?? []
        return items.map { item in
            var contents = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                contents[type] = item.data(forType: type)
            }
            return contents
        }
    }

    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

// MARK: - Suffix and mouse helpers

extension EditingDriver {

    /// `true` when the selected text does not contain the address bar suffix (it always starts with the “ – ” separator).
    func selectionExcludesSuffix(_ text: String?) -> Bool {
        !(text ?? "").contains(Self.suffixSeparator)
    }

    /// A point `x`/`y` points from the top left of the mouse target. Negative values count from the right/bottom edge;
    /// `y` defaults to the vertical center.
    func point(x: CGFloat, y: CGFloat? = nil) -> XCUICoordinate {
        let target = mouseTarget ?? element
        let size = target.frame.size
        let resolvedX = x >= 0 ? x : size.width + x
        let resolvedY = y.map { $0 >= 0 ? $0 : size.height + $0 } ?? size.height / 2
        let origin = target.coordinate(withNormalizedOffset: .zero)
        return origin.withOffset(CGVector(dx: resolvedX, dy: resolvedY))
    }

    func click(_ point: XCUICoordinate) {
        point.click()
    }

    func doubleClick(_ point: XCUICoordinate) {
        point.doubleClick()
    }

    /// XCUI has no triple click: post three left clicks with an increasing click count at the point.
    func tripleClick(_ point: XCUICoordinate) {
        point.hover()
        let location = point.screenPoint
        let source = CGEventSource(stateID: .hidSystemState)
        for clickState in 1...3 {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
                event?.post(tap: .cghidEventTap)
            }
        }
        Thread.sleep(forTimeInterval: 0.3)
    }

    func shiftClick(_ point: XCUICoordinate) {
        XCUIElement.perform(withKeyModifiers: .shift) {
            point.click()
        }
    }

    func drag(from start: XCUICoordinate, to end: XCUICoordinate) {
        start.click(forDuration: 0.3, thenDragTo: end)
    }
}
