//
//  CarbonGlobalShortcutRegistrar.swift
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
import Carbon.HIToolbox
import os.log

/// Carbon's `RegisterEventHotKey` is the only global-hotkey route needing no Accessibility grant;
/// `NSEvent.addGlobalMonitorForEvents` silently drops key events until one is given.
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {

    private enum Constants {
        /// Four-char signature ("DDGP") scoping our hot key IDs to this app.
        static let signature = OSType(0x44_44_47_50)
        static let promptBarHotKeyID: UInt32 = 1
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    private(set) var registeredShortcut: PromptBarShortcut?

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @discardableResult
    func register(_ shortcut: PromptBarShortcut, handler: @escaping () -> Void) -> Bool {
        unregister()

        guard installEventHandlerIfNeeded() else { return false }

        let hotKeyID = EventHotKeyID(signature: Constants.signature, id: Constants.promptBarHotKeyID)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                        Self.carbonModifiers(from: shortcut.modifierFlags),
                                        hotKeyID,
                                        GetApplicationEventTarget(),
                                        0,
                                        &reference)

        guard status == noErr, let reference else {
            Logger.general.error("Prompt Bar: global shortcut registration failed with status \(status)")
            return false
        }

        hotKeyRef = reference
        self.handler = handler
        registeredShortcut = shortcut
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        handler = nil
        registeredShortcut = nil
    }

    fileprivate func handleHotKeyPressed() {
        handler?()
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandlerRef == nil else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var reference: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                        promptBarHotKeyEventHandler,
                                        1,
                                        &eventType,
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        &reference)

        guard status == noErr else {
            Logger.general.error("Prompt Bar: global shortcut event handler install failed with status \(status)")
            return false
        }

        eventHandlerRef = reference
        return true
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }
}

/// C callback: Carbon can't carry a Swift closure, so the registrar is passed as `userData`.
private let promptBarHotKeyEventHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
    registrar.handleHotKeyPressed()
    return noErr
}
