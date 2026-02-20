//
//  WebExtensionWindowTabProviding.swift
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

import WebKit

/// Provides platform-specific window and tab operations for web extensions.
/// This protocol abstracts the platform-specific implementations needed by WKWebExtensionControllerDelegate.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
public protocol WebExtensionWindowTabProviding: AnyObject {

    /// Returns the open windows for the given extension context.
    /// The focused window should be first in the array.
    func openWindows(for context: WKWebExtensionContext) -> [any WKWebExtensionWindow]

    /// Returns the currently focused window for the given extension context.
    func focusedWindow(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)?

    /// Opens a new window with the given configuration.
    func openNewWindow(using configuration: WKWebExtension.WindowConfiguration,
                       for context: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)?

    /// Opens a new tab with the given configuration.
    func openNewTab(using configuration: WKWebExtension.TabConfiguration,
                    for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)?

    /// Presents the action popup for the given extension context.
    func presentPopup(_ action: WKWebExtension.Action,
                      for context: WKWebExtensionContext) async throws
}
