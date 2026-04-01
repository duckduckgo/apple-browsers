//
//  ScriptletStoring.swift
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

/// Persistent storage for fetched scriptlet files and their metadata.
///
/// This protocol combines two concerns:
/// - **Cache management**: saving/loading fetched scriptlet files to disk and tracking
///   which version is cached (used by ``ScriptletManager``).
/// - **Installed version tracking** (inherited from ``ScriptletInstallationTracking``):
///   recording which version has been installed into a live extension directory
///   (used by ``WebExtensionScriptletCoordinator``).
@available(macOS 15.4, iOS 18.4, *)
public protocol ScriptletStoring: ScriptletInstallationTracking {

    /// The root directory where cached scriptlet files are stored.
    var cacheRootDirectory: URL { get }

    /// Returns the version string of the cached scriptlets, or `nil` if nothing is cached.
    func cachedVersion(for extensionType: DuckDuckGoWebExtensionType) -> String?

    /// Loads cached scriptlets from disk, verifying that all referenced files still exist.
    /// Returns `nil` if no cache exists or all files are missing.
    func loadCached(for extensionType: DuckDuckGoWebExtensionType) -> CachedScriptlets?

    /// Atomically saves fetched scriptlets to disk and updates metadata.
    /// The previous cache is backed up during the write and restored on failure.
    @discardableResult
    func save(_ fetched: [FetchedScriptlet], version: String, for extensionType: DuckDuckGoWebExtensionType) throws -> [Scriptlet]

    /// Removes cached files and metadata for the given extension type.
    /// Does not affect the installed version tracking.
    func clearCache(for extensionType: DuckDuckGoWebExtensionType)

    /// Removes both cached files and installed version tracking for the given extension type.
    func clear(for extensionType: DuckDuckGoWebExtensionType)

    /// Removes the entire cache directory, all metadata, and all installed version records.
    func clearAll()
}
