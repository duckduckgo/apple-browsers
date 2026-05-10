//
//  ScriptletStore.swift
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
import os.log

/// Persistent storage for fetched scriptlet files and their metadata.
///
/// `ScriptletStore` manages two distinct concepts:
///
/// - **Cached version** (`cachedVersion` / `loadCached` / `save`): the version of scriptlet
///   files downloaded from the server and written to the cache directory on disk.
///   Tracked via JSON metadata in `UserDefaults`.
///
/// - **Installed version** (`installedVersion` / `setInstalledVersion`): the version that has
///   been copied from the cache into a live web extension's directory by ``ScriptletInstaller``.
///   Tracked separately in `UserDefaults` so the coordinator can skip redundant installs.
///
/// ## Disk layout
///
/// ```
/// baseDirectory/
///   <extensionType>/         (e.g. "adBlockingExtension")
///     <version>/             (sanitized version string)
///       <scriptlet files>    (e.g. "scriptlets/scriptlet.js")
/// ```
///
/// ## Atomic saves
///
/// ``save(_:version:for:)`` writes new files to a temporary directory first, then atomically
/// swaps them into place. The previous version is kept as a `.backup` directory during the swap
/// and restored if the move fails, preventing partial writes from corrupting the cache.
///
/// ## Clearing
///
/// - ``clearCache(for:)`` removes cached files and metadata but preserves the installed version.
/// - ``clear(for:)`` removes both cached files and the installed version tracking.
/// - ``clearAll()`` removes the entire base directory and all metadata.
@available(macOS 15.4, iOS 18.4, *)
public final class ScriptletStore: ScriptletStoring {

    private let baseDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let metadataKey = "scriptlets.cache.metadata"
    private let installedVersionKeyPrefix = "scriptlets.installed.version."

    public init(
        baseDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.defaults = defaults
        self.fileManager = fileManager
    }

    public var cacheRootDirectory: URL {
        baseDirectory
    }

    public func cachedVersion(for extensionType: DuckDuckGoWebExtensionType) -> String? {
        loadMetadata()?.extensions[extensionType.rawValue]?.version
    }

    public func loadCached(for extensionType: DuckDuckGoWebExtensionType) -> CachedScriptlets? {
        guard let metadata = loadMetadata(),
              let cached = metadata.extensions[extensionType.rawValue] else {
            return nil
        }

        let validScriptlets = cached.scriptlets.filter { scriptlet in
            let fileURL = baseDirectory.appendingPathComponent(scriptlet.relativeCachedPath)
            let exists = fileManager.fileExists(atPath: fileURL.path)
            if !exists {
                Logger.webExtensions.warning("[Scriptlets] Cached file missing: \(scriptlet.relativeCachedPath)")
            }
            return exists
        }

        guard !validScriptlets.isEmpty else { return nil }

        return CachedScriptlets(version: cached.version, scriptlets: validScriptlets)
    }

    @discardableResult
    public func save(_ fetched: [FetchedScriptlet], version: String, for extensionType: DuckDuckGoWebExtensionType) throws -> [Scriptlet] {
        let extensionDirectory = self.extensionDirectory(for: extensionType)
        let safeVersion = sanitizedDirectoryName(version)
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(safeVersion)

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        let resolvedTempDirectory = tempDirectory.standardizedFileURL.resolvingSymlinksInPath()

        var scriptlets: [Scriptlet] = []
        let extensionTypeRawValue = extensionType.rawValue

        for item in fetched {
            try ScriptletPathSafety.validateName(item.descriptor.name)

            let relativeCachedPath = "\(extensionTypeRawValue)/\(safeVersion)/\(item.descriptor.name)"
            let scriptlet = Scriptlet(path: item.descriptor.name, relativeCachedPath: relativeCachedPath)
            let file = resolvedTempDirectory.appendingPathComponent(item.descriptor.name)
            try ScriptletPathSafety.ensureContained(file, within: resolvedTempDirectory, name: item.descriptor.name)

            let fileDirectory = file.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: fileDirectory.path) {
                try fileManager.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
            }

            try item.data.write(to: file, options: .atomic)
            scriptlets.append(scriptlet)
        }

        let backupDirectory = extensionDirectory.appendingPathExtension("backup")

        try? fileManager.removeItem(at: backupDirectory)
        try? fileManager.moveItem(at: extensionDirectory, to: backupDirectory)

        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
            try fileManager.moveItem(at: tempDirectory.deletingLastPathComponent(), to: extensionDirectory)
            try? fileManager.removeItem(at: backupDirectory)

            updateMetadata(for: extensionType, version: version, scriptlets: scriptlets)
            return scriptlets
        } catch {
            Logger.webExtensions.error("[Scriptlets] Failed to save scriptlets for '\(extensionType.rawValue)', restoring backup: \(error)")
            try? fileManager.moveItem(at: backupDirectory, to: extensionDirectory)
            throw ScriptletError.storageFailed(underlying: "\(error)")
        }
    }

    public func clearCache(for extensionType: DuckDuckGoWebExtensionType) {
        let extensionDirectory = self.extensionDirectory(for: extensionType)
        try? fileManager.removeItem(at: extensionDirectory)

        var metadata = loadMetadata() ?? ScriptletCacheMetadata()
        metadata.extensions.removeValue(forKey: extensionType.rawValue)
        saveMetadata(metadata)
    }

    public func clear(for extensionType: DuckDuckGoWebExtensionType) {
        clearCache(for: extensionType)
        clearInstalledVersion(for: extensionType)
    }

    public func clearAll() {
        try? fileManager.removeItem(at: baseDirectory)
        defaults.removeObject(forKey: metadataKey)
        clearAllInstalledVersions()
    }

    public func installedVersion(for extensionType: DuckDuckGoWebExtensionType) -> String? {
        defaults.string(forKey: installedVersionKey(for: extensionType))
    }

    public func setInstalledVersion(_ version: String, for extensionType: DuckDuckGoWebExtensionType) {
        defaults.set(version, forKey: installedVersionKey(for: extensionType))
    }

    public func clearInstalledVersion(for extensionType: DuckDuckGoWebExtensionType) {
        defaults.removeObject(forKey: installedVersionKey(for: extensionType))
    }

    private func installedVersionKey(for extensionType: DuckDuckGoWebExtensionType) -> String {
        installedVersionKeyPrefix + extensionType.rawValue
    }

    private func clearAllInstalledVersions() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(installedVersionKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func extensionDirectory(for extensionType: DuckDuckGoWebExtensionType) -> URL {
        baseDirectory.appendingPathComponent(extensionType.rawValue)
    }

    private static let allowedDirectoryCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))

    /// Strips characters not safe for a single directory component using an allowlist
    /// of alphanumerics, dots, hyphens, and underscores.
    private func sanitizedDirectoryName(_ value: String) -> String {
        let sanitized = String(value.unicodeScalars.map {
            Self.allowedDirectoryCharacters.contains($0) ? Character($0) : Character("_")
        })
        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
            return "_"
        }
        return sanitized
    }

    private func loadMetadata() -> ScriptletCacheMetadata? {
        guard let data = defaults.data(forKey: metadataKey) else {
            return nil
        }

        do {
            let metadata = try JSONDecoder().decode(ScriptletCacheMetadata.self, from: data)
            return metadata
        } catch {
            Logger.webExtensions.error("[Scriptlets] Failed to decode metadata: \(error)")
            return nil
        }
    }

    private func saveMetadata(_ metadata: ScriptletCacheMetadata) {
        do {
            let data = try JSONEncoder().encode(metadata)
            defaults.set(data, forKey: metadataKey)
        } catch {
            Logger.webExtensions.error("[Scriptlets] Failed to encode metadata: \(error)")
        }
    }

    private func updateMetadata(for extensionType: DuckDuckGoWebExtensionType, version: String, scriptlets: [Scriptlet]) {
        var metadata = loadMetadata() ?? ScriptletCacheMetadata()
        metadata.extensions[extensionType.rawValue] = CachedScriptlets(version: version, scriptlets: scriptlets)
        saveMetadata(metadata)
    }
}
