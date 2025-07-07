//
//  SwiftUIContextMenuRetainCycleFix.swift
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

import AppKit
import Common
import Foundation

/// A utility to fix retain cycles in SwiftUI context menus
/// This fix addresses a known issue where SwiftUI context menus can create retain cycles
/// between the menu and its responder, leading to memory leaks.
///
/// The retain cycle is caused by the `AppKitMenuDelegate` class holding a strong reference to the `ContextMenuResponder`
/// and the `ContextMenuResponder` holding a strong reference to the `AppKitMenuDelegate`.
///
/// The fix works by:
/// 1. Swizzling NSMenu._popUpContextMenu to get access to `SwiftUI.ContextMenuResponder.AppKitMenuDelegate` class
/// 2. Swizzling the `menuDidClose` method in the `AppKitMenuDelegate` class to break the retain cycle
/// 3. Using a utility struct to break the retain cycle by nullifying a specific field in the object
enum SwiftUIContextMenuRetainCycleFix {

    fileprivate static var isMenuDidCloseSwizzled = false

    static func setUp() {
        _=NSMenu.swizzle_popUpContextMenuOnce
    }

}

/// A utility struct that helps break retain cycles by nullifying specific object references
struct ReflectionPropertySetter {

    /// Breaks a retain cycle by nullifying a specific field in an object
    /// - Parameters:
    ///   - object: The object containing the field to nullify
    ///   - fieldName: The name of the field to nullify
    func breakRetainCycle(in object: AnyObject, nullifying fieldName: String) {
        let mirror = Mirror(reflecting: object)

        // Step 1: Locate the object reference in the object's mirror
        guard let targetField = mirror.children.first(where: { $0.label == fieldName })?.value as AnyObject? else {
            assertionFailure("Field \(fieldName) not found in \(String(describing: object))")
            return
        }

        // Get raw pointers for memory manipulation
        let targetPtr = Unmanaged.passUnretained(targetField).toOpaque()
        let objectPtr = UnsafeRawPointer(Unmanaged.passUnretained(object).toOpaque())
        let objectSize = class_getInstanceSize(type(of: object))

        let pointerStride = MemoryLayout<UnsafeRawPointer>.stride
        let pointerCount = objectSize / pointerStride

        // Step 2: Scan each pointer-sized slot in the object's memory
        for i in 0..<pointerCount {
            let offset = i * pointerStride
            let candidate = objectPtr.load(fromByteOffset: offset, as: UnsafeRawPointer.self)

            if candidate == targetPtr {
                // Step 3: Safely nullify the field by writing nil to its memory location
                let mutablePtr = UnsafeMutableRawPointer(mutating: objectPtr)
                mutablePtr
                    .advanced(by: offset)
                    .assumingMemoryBound(to: Optional<AnyObject>.self)
                    .pointee = nil
                return
            }
        }

        assertionFailure("Field '\(fieldName)' not found in scanned memory range of \(String(describing: object)).")
    }

}

extension NSMenu {

    fileprivate static var swizzle_popUpContextMenuOnce: Void = { // swiftlint:disable:this identifier_name
        let originalSelector = NSSelectorFromString("_" + NSStringFromSelector(#selector(popUpContextMenu(_:with:for:with:))))
        let swizzledSelector = #selector(swizzled_popUpContextMenu(_:withEvent:forView:withFont:))

        guard let originalMethod = class_getInstanceMethod(NSMenu.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSMenu.self, swizzledSelector) else {
            assertionFailure("Failed to swizzle NSMenu.popUpContextMenu")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc dynamic func swizzled_popUpContextMenu(_ menu: NSMenu, withEvent event: NSEvent, forView view: NSView, withFont font: NSFont) {
        if !SwiftUIContextMenuRetainCycleFix.isMenuDidCloseSwizzled,
           let delegate = menu.delegate as? NSObject,
           delegate.className.matches(regex(".*SwiftUI.*ContextMenuResponder.*AppKitMenuDelegate")) {
            SwiftUIContextMenuRetainCycleFix.isMenuDidCloseSwizzled = true

            Self.swizzleContextMenuResponderMenuDidClose(in: type(of: delegate))
        }
        self.swizzled_popUpContextMenu(menu, withEvent: event, forView: view, withFont: font)
    }

    private static func swizzleContextMenuResponderMenuDidClose(in cls: AnyClass) {
        guard let originalMethod = class_getInstanceMethod(cls, #selector(NSMenuDelegate.menuDidClose)),
              let swizzledMethod = class_getInstanceMethod(cls, #selector(swizzled_appKitMenuDelegate_menuDidClose(_:))) else {
            assertionFailure("Failed to find method \(cls).menuDidClose")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

}

extension NSObject {

    @objc fileprivate dynamic func swizzled_appKitMenuDelegate_menuDidClose(_ menu: NSMenu) {
        self.swizzled_appKitMenuDelegate_menuDidClose(menu)

        guard let menuResponder = Mirror(reflecting: self).children.first(where: { $0.label == "menuResponder" })?.value as AnyObject? else {
            assertionFailure("Add macOS version check to disable this fix in newer versions of macOS if the issue is fixed")
            return
        }
        // we‘re nullifying the `ContextMenuResponder.delegate` lazy var storage
        // because `AppKitMenuDelegate.menuResponder` is likely to be converted to a weak var
        // when (if) the bug is fixed and nullifying it would result in over-release
        ReflectionPropertySetter().breakRetainCycle(in: menuResponder, nullifying: "$__lazy_storage_$_delegate")
    }

}
