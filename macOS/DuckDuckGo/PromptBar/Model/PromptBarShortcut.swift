//
//  PromptBarShortcut.swift
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
import Carbon

/// A global keyboard shortcut for the Prompt Bar: a virtual key code plus modifier flags.
struct PromptBarShortcut: Equatable, Codable {

    /// Layout-independent virtual key code (`kVK_*`).
    let keyCode: UInt16

    private let rawModifierFlags: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawModifierFlags)
    }

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.rawModifierFlags = modifierFlags
            .intersection([.command, .option, .control, .shift])
            .rawValue
    }

    static let defaultShortcut = PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .option)

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }
}

// MARK: - Validation

extension PromptBarShortcut {

    /// A global shortcut needs ⌘, ⌥ or ⌃ — bare keys or shift-only combos would swallow typing.
    var hasRequiredModifiers: Bool {
        !modifierFlags.isDisjoint(with: [.command, .option, .control])
    }

    /// Name of the system feature this combo is reserved for, or nil if it's free to use.
    var reservedSystemOwnerName: String? {
        Self.reservedShortcuts.first { $0.shortcut == self }?.ownerName
    }

    private static let reservedShortcuts: [(shortcut: PromptBarShortcut, ownerName: String)] = [
        (PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: .command), "Spotlight"),
        (PromptBarShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.command, .option]), "Spotlight"),
        (PromptBarShortcut(keyCode: UInt16(kVK_Tab), modifierFlags: .command), "App Switcher"),
    ]
}

// MARK: - Display

extension PromptBarShortcut {

    /// Modifier symbols in canonical macOS order (⌃⌥⇧⌘), one per keycap chip.
    var modifierSymbols: [String] {
        var symbols = [String]()
        if modifierFlags.contains(.control) { symbols.append("⌃") }
        if modifierFlags.contains(.option) { symbols.append("⌥") }
        if modifierFlags.contains(.shift) { symbols.append("⇧") }
        if modifierFlags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    /// Human-readable name of the non-modifier key ("Space", "A", "F5", "→").
    var keyDisplayString: String {
        if let specialKeyName = Self.specialKeyNames[Int(keyCode)] {
            return specialKeyName
        }
        if let character = Self.character(for: keyCode) {
            return character.uppercased()
        }
        return "?"
    }

    /// Single-string form for error messages, e.g. "⌘Space".
    var displayString: String {
        (modifierSymbols + [keyDisplayString]).joined()
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: UserText.promptBarShortcutSpaceKey,
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Translates a virtual key code using the current keyboard layout, so letters
    /// match what the user's layout actually types (e.g. AZERTY vs QWERTY).
    private static func character(for keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var characterCount = 0

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layoutPointer = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(layoutPointer,
                                  keyCode,
                                  UInt16(kUCKeyActionDisplay),
                                  0,
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKeyState,
                                  characters.count,
                                  &characterCount,
                                  &characters)
        }

        guard status == noErr, characterCount > 0 else { return nil }
        let result = String(utf16CodeUnits: characters, count: characterCount)
        return result.isEmpty ? nil : result
    }
}
