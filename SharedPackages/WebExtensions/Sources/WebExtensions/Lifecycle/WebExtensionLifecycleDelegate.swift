//
//  WebExtensionLifecycleDelegate.swift
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

import Foundation

/// Delegate for receiving lifecycle events from the web extension manager.
/// Implement this protocol to perform platform-specific actions such as migrations or UI updates.
@available(macOS 15.4, *)
public protocol WebExtensionLifecycleDelegate: AnyObject {

    /// Called before loading extensions. Use this to perform migrations or other setup.
    func webExtensionManagerWillLoadExtensions(_ manager: WebExtensionManaging)

    /// Called when extensions have been updated (installed, uninstalled, or loaded).
    func webExtensionManagerDidUpdateExtensions(_ manager: WebExtensionManaging)
}

/// Default implementations to make all methods optional.
@available(macOS 15.4, *)
public extension WebExtensionLifecycleDelegate {

    func webExtensionManagerWillLoadExtensions(_ manager: WebExtensionManaging) {}

    func webExtensionManagerDidUpdateExtensions(_ manager: WebExtensionManaging) {}
}
