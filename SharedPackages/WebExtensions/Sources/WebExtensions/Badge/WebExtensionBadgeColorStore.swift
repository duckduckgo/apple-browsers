//
//  WebExtensionBadgeColorStore.swift
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

import Foundation
import WebKit

/// The color strings extensions set with `action.setBadgeBackgroundColor` and `action.setBadgeTextColor`.
/// A color applies on every tab, since WebKit doesn't tell which of our tabs an extension's `tabId` is.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public final class WebExtensionBadgeColorStore {

    // Weak keys, so an unloaded extension's colors go with its context.
    private let backgroundColors = NSMapTable<WKWebExtensionContext, NSString>.weakToStrongObjects()
    private let textColors = NSMapTable<WKWebExtensionContext, NSString>.weakToStrongObjects()

    nonisolated public init() {}

    /// The color the extension set with `action.setBadgeBackgroundColor`. `nil` means the app's default.
    public func backgroundColor(for context: WKWebExtensionContext) -> String? {
        backgroundColors.object(forKey: context) as String?
    }

    /// The color the extension set with `action.setBadgeTextColor`. `nil` means the app's default.
    public func textColor(for context: WKWebExtensionContext) -> String? {
        textColors.object(forKey: context) as String?
    }

    /// Returns whether the color changed.
    func setBackgroundColor(_ color: String, for context: WKWebExtensionContext) -> Bool {
        set(color, for: context, in: backgroundColors)
    }

    /// Returns whether the color changed.
    func setTextColor(_ color: String, for context: WKWebExtensionContext) -> Bool {
        set(color, for: context, in: textColors)
    }

    private func set(_ color: String, for context: WKWebExtensionContext, in colors: NSMapTable<WKWebExtensionContext, NSString>) -> Bool {
        guard colors.object(forKey: context) as String? != color else { return false }
        colors.setObject(color as NSString, forKey: context)
        return true
    }
}
