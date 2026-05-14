//
//  XCUIDeviceExtension.swift
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

import XCTest
import ObjectiveC

private var activeKeyModifiersKey: UInt8 = 0

extension XCUIDevice {

    /// Currently active key modifiers (used for simulating key hold)
    static var activeKeyModifiers: XCUIElement.KeyModifierFlags? {
        get {
            return objc_getAssociatedObject(self, &activeKeyModifiersKey) as? XCUIElement.KeyModifierFlags
        }
        set {
            objc_setAssociatedObject(self, &activeKeyModifiersKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Swizzles XCUIElement.perform(withKeyModifiers:block:) to store the active key modifiers.
    static let swizzlePerformWithKeyModifiersOnce: Void = {
        let originalSelector = #selector(XCUIElement.perform(withKeyModifiers:block:))
        let swizzledSelector = #selector(XCUIDevice.swizzled_perform(withKeyModifiers:block:))

        guard let originalMethod = class_getInstanceMethod(XCUIDevice.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(XCUIDevice.self, swizzledSelector) else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    /// Swizzled implementation of XCUIElement.perform(withKeyModifiers:block:) to store the active key modifiers.
    /// This is used to simulate keyDown/keyUp scenarios (see `UITestCase.keyEventOverride` in `UITests.swift`).
    @objc private func swizzled_perform(withKeyModifiers flags: XCUIElement.KeyModifierFlags, block: () -> Void) {
        let previousFlags = XCUIDevice.activeKeyModifiers
        XCUIDevice.activeKeyModifiers = flags

        // Call the original implementation
        swizzled_perform(withKeyModifiers: flags, block: block)

        XCUIDevice.activeKeyModifiers = previousFlags
    }
}
