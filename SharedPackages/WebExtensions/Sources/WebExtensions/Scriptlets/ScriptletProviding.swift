//
//  ScriptletProviding.swift
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

import Combine
import Foundation

/// Provides scriptlet availability and lifecycle management for web extension types.
///
/// Conforming types manage fetching, caching, and publishing scriptlet state.
/// The primary consumer is ``WebExtensionScriptletCoordinator``, which subscribes
/// to availability changes and triggers installations.
@MainActor
@available(macOS 15.4, iOS 18.4, *)
public protocol ScriptletProviding {

    /// Activates scriptlet management for the given extension type.
    /// Loads cached scriptlets, fetches updates if the config version has changed,
    /// and begins listening for future config changes.
    func start(for extensionType: DuckDuckGoWebExtensionType) async

    /// Returns the current availability snapshot for the given extension type.
    func availability(for extensionType: DuckDuckGoWebExtensionType) -> ScriptletAvailability

    /// Returns a publisher that emits availability changes for the given extension type.
    /// The coordinator subscribes to this (dropping the first value) to trigger installations
    /// when new scriptlets become available.
    func availabilityPublisher(for extensionType: DuckDuckGoWebExtensionType) -> AnyPublisher<ScriptletAvailability, Never>

    /// Returns the current scriptlets if available or updating, `nil` if not available.
    func scriptlets(for extensionType: DuckDuckGoWebExtensionType) -> [Scriptlet]?

    /// Returns the cached version string for the given extension type, or `nil` if nothing is cached.
    func scriptletVersion(for extensionType: DuckDuckGoWebExtensionType) -> String?

    /// Returns `true` if scriptlets are available (cached or fetched) for the given extension type.
    func isReady(for extensionType: DuckDuckGoWebExtensionType) -> Bool

    /// Checks whether the cached version differs from the config manifest and fetches updates if so.
    func refreshIfNeeded(for extensionType: DuckDuckGoWebExtensionType) async

    /// Deactivates scriptlet management for the given extension type and cancels any in-flight fetches.
    func stop(for extensionType: DuckDuckGoWebExtensionType)

    /// Removes all cached scriptlets from disk and resets availability to `.notAvailable` for all types.
    func clearCachedScriptlets()
}
