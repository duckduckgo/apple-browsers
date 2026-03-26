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

    public init(
        baseDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.defaults = defaults
        self.fileManager = fileManager
    }

    public func loadCached(for extensionType: DuckDuckGoWebExtensionType) -> CachedScriptlets? {
        Logger.webExtensions.debug("[Scriptlets] 📂 Loading cached scriptlets for '\(extensionType.rawValue)'")

        guard let metadata = loadMetadata(),
              let extensionMetadata = metadata.extensions[extensionType.rawValue] else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No cached metadata found for '\(extensionType.rawValue)'")
            return nil
        }

        let extensionDirectory = self.extensionDirectory(for: extensionType)

        guard fileManager.fileExists(atPath: extensionDirectory.path) else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ Cache directory does not exist for '\(extensionType.rawValue)'")
            return nil
        }

        let scriptlets = extensionMetadata.scriptlets.compactMap { fileMetadata -> Scriptlet? in
            let fileURL = extensionDirectory.appendingPathComponent(fileMetadata.cachedFileName)
            guard let data = try? Data(contentsOf: fileURL) else {
                Logger.webExtensions.warning("[Scriptlets] ⚠️ Failed to read cached file: \(fileMetadata.cachedFileName)")
                return nil
            }
            return Scriptlet(name: fileMetadata.targetPath, content: data)
        }

        guard !scriptlets.isEmpty else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlet files found in cache for '\(extensionType.rawValue)'")
            return nil
        }

        Logger.webExtensions.info("[Scriptlets] ✅ Loaded \(scriptlets.count) scriptlet(s) from cache for '\(extensionType.rawValue)' v\(extensionMetadata.version)")
        return CachedScriptlets(version: extensionMetadata.version, scriptlets: scriptlets)
    }

    public func save(_ scriptlets: [Scriptlet], version: String, for extensionType: DuckDuckGoWebExtensionType, withTargetPaths targetPaths: [String: String]) throws {
        Logger.webExtensions.debug("[Scriptlets] 💾 Saving \(scriptlets.count) scriptlet(s) v\(version) for '\(extensionType.rawValue)'")

        let extensionDirectory = self.extensionDirectory(for: extensionType)
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        Logger.webExtensions.debug("[Scriptlets] 📝 Writing scriptlets to temporary directory")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)

        var fileMetadataArray: [ScriptletFileMetadata] = []

        for scriptlet in scriptlets {
            let file = tempDirectory.appendingPathComponent(scriptlet.fileName)
            try scriptlet.content.write(to: file, options: .atomic)

            guard let targetPath = targetPaths[scriptlet.name] else {
                Logger.webExtensions.warning("[Scriptlets] ⚠️ No target path found for scriptlet '\(scriptlet.name)', using name as path")
                fileMetadataArray.append(ScriptletFileMetadata(targetPath: scriptlet.name, cachedFileName: scriptlet.fileName))
                continue
            }

            fileMetadataArray.append(ScriptletFileMetadata(targetPath: targetPath, cachedFileName: scriptlet.fileName))
        }

        let backupDirectory = extensionDirectory.appendingPathExtension("backup")

        Logger.webExtensions.debug("[Scriptlets] 🔄 Creating backup and moving to final location")
        try? fileManager.removeItem(at: backupDirectory)
        try? fileManager.moveItem(at: extensionDirectory, to: backupDirectory)

        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
            try fileManager.moveItem(at: tempDirectory, to: extensionDirectory)
            try? fileManager.removeItem(at: backupDirectory)

            updateMetadata(for: extensionType, version: version, scriptlets: fileMetadataArray)

            Logger.webExtensions.info("[Scriptlets] ✅ Successfully saved \(scriptlets.count) scriptlet(s) v\(version) for '\(extensionType.rawValue)'")
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

        Logger.webExtensions.info("[Scriptlets] ✅ Cleared scriptlet cache for '\(extensionType.rawValue)'")
    }

    public func clearAll() {
        Logger.webExtensions.debug("[Scriptlets] 🗑️ Clearing all cached scriptlets")
        try? fileManager.removeItem(at: baseDirectory)
        defaults.removeObject(forKey: metadataKey)
        Logger.webExtensions.info("[Scriptlets] ✅ Cleared all scriptlet caches")
    }

    private func extensionDirectory(for extensionType: DuckDuckGoWebExtensionType) -> URL {
        baseDirectory.appendingPathComponent(extensionType.rawValue)
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

    private func updateMetadata(for extensionType: DuckDuckGoWebExtensionType, version: String, scriptlets: [ScriptletFileMetadata]) {
        var metadata = loadMetadata() ?? ScriptletCacheMetadata()

        let extensionMetadata = ExtensionScriptletMetadata(
            extensionType: extensionType.rawValue,
            version: version,
            scriptlets: scriptlets
        )

        metadata.extensions[extensionType.rawValue] = extensionMetadata
        saveMetadata(metadata)
    }
}
