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

    public func loadCached(for extensionType: DuckDuckGoWebExtensionType) -> CachedScriptlets? {
        Logger.webExtensions.debug("[Scriptlets] 📂 Loading cached scriptlets for '\(extensionType.rawValue)'")

        guard let metadata = loadMetadata(),
              let cached = metadata.extensions[extensionType.rawValue] else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No cached metadata found for '\(extensionType.rawValue)'")
            return nil
        }

        let validScriptlets = cached.scriptlets.filter { scriptlet in
            let fileURL = baseDirectory.appendingPathComponent(scriptlet.relativeCachedPath)
            let exists = fileManager.fileExists(atPath: fileURL.path)
            if !exists {
                Logger.webExtensions.warning("[Scriptlets] ⚠️ Cached file missing: \(scriptlet.relativeCachedPath)")
            }
            return exists
        }

        guard !validScriptlets.isEmpty else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlet files found in cache for '\(extensionType.rawValue)'")
            return nil
        }

        Logger.webExtensions.info("[Scriptlets] ✅ Loaded \(validScriptlets.count) scriptlet(s) from cache for '\(extensionType.rawValue)' v\(cached.version)")
        return CachedScriptlets(version: cached.version, scriptlets: validScriptlets)
    }

    @discardableResult
    public func save(_ fetched: [FetchedScriptlet], version: String, for extensionType: DuckDuckGoWebExtensionType) throws -> [Scriptlet] {
        Logger.webExtensions.debug("[Scriptlets] 💾 Saving \(fetched.count) scriptlet(s) v\(version) for '\(extensionType.rawValue)'")

        let extensionDirectory = self.extensionDirectory(for: extensionType)
        let safeVersion = sanitizedDirectoryName(version)
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(safeVersion)

        Logger.webExtensions.debug("[Scriptlets] 📝 Writing scriptlets to temporary directory")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)

        var scriptlets: [Scriptlet] = []
        let extensionTypeRawValue = extensionType.rawValue

        for item in fetched {
            let relativeCachedPath = "\(extensionTypeRawValue)/\(safeVersion)/\(item.descriptor.name)"
            let scriptlet = Scriptlet(path: item.descriptor.name, relativeCachedPath: relativeCachedPath)
            let file = tempDirectory.appendingPathComponent(item.descriptor.name)

            let fileDirectory = file.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: fileDirectory.path) {
                try fileManager.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
            }

            try item.data.write(to: file, options: .atomic)
            scriptlets.append(scriptlet)
        }

        let backupDirectory = extensionDirectory.appendingPathExtension("backup")

        Logger.webExtensions.debug("[Scriptlets] 🔄 Creating backup and moving to final location")
        try? fileManager.removeItem(at: backupDirectory)
        try? fileManager.moveItem(at: extensionDirectory, to: backupDirectory)

        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
            try fileManager.moveItem(at: tempDirectory.deletingLastPathComponent(), to: extensionDirectory)
            try? fileManager.removeItem(at: backupDirectory)

            updateMetadata(for: extensionType, version: version, scriptlets: scriptlets)

            Logger.webExtensions.info("[Scriptlets] ✅ Successfully saved \(fetched.count) scriptlet(s) v\(version) for '\(extensionType.rawValue)'")
            return scriptlets
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to save scriptlets for '\(extensionType.rawValue)', restoring backup: \(error.localizedDescription)")
            try? fileManager.moveItem(at: backupDirectory, to: extensionDirectory)
            throw ScriptletError.storageFailed(underlying: error.localizedDescription)
        }
    }

    public func clear(for extensionType: DuckDuckGoWebExtensionType) {
        Logger.webExtensions.debug("[Scriptlets] 🗑️ Clearing cached scriptlets for '\(extensionType.rawValue)'")
        let extensionDirectory = self.extensionDirectory(for: extensionType)
        try? fileManager.removeItem(at: extensionDirectory)

        var metadata = loadMetadata() ?? ScriptletCacheMetadata()
        metadata.extensions.removeValue(forKey: extensionType.rawValue)
        saveMetadata(metadata)
        clearInstalledVersion(for: extensionType)

        Logger.webExtensions.info("[Scriptlets] ✅ Cleared scriptlet cache for '\(extensionType.rawValue)'")
    }

    public func clearAll() {
        Logger.webExtensions.debug("[Scriptlets] 🗑️ Clearing all cached scriptlets")
        try? fileManager.removeItem(at: baseDirectory)
        defaults.removeObject(forKey: metadataKey)
        clearAllInstalledVersions()
        Logger.webExtensions.info("[Scriptlets] ✅ Cleared all scriptlet caches")
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

    /// Replaces path-unsafe characters so the version can be used as a single directory component.
    private func sanitizedDirectoryName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
    }

    private func loadMetadata() -> ScriptletCacheMetadata? {
        guard let data = defaults.data(forKey: metadataKey) else {
            return nil
        }

        do {
            let metadata = try JSONDecoder().decode(ScriptletCacheMetadata.self, from: data)
            return metadata
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to decode metadata: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveMetadata(_ metadata: ScriptletCacheMetadata) {
        do {
            let data = try JSONEncoder().encode(metadata)
            defaults.set(data, forKey: metadataKey)
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to encode metadata: \(error.localizedDescription)")
        }
    }

    private func updateMetadata(for extensionType: DuckDuckGoWebExtensionType, version: String, scriptlets: [Scriptlet]) {
        var metadata = loadMetadata() ?? ScriptletCacheMetadata()
        metadata.extensions[extensionType.rawValue] = CachedScriptlets(version: version, scriptlets: scriptlets)
        saveMetadata(metadata)
    }
}
