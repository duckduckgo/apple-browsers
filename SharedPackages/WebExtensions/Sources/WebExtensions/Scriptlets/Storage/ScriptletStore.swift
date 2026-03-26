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

public final class ScriptletStore: ScriptletStoring {

    private let baseDirectory: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let metadataKey = "scriptlets.cached.version"

    public init(
        baseDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.defaults = defaults
        self.fileManager = fileManager
    }

    public func loadCached() -> CachedScriptlets? {
        Logger.webExtensions.debug("[Scriptlets] 📂 Loading cached scriptlets from \(self.baseDirectory.path)")
        guard let version = defaults.string(forKey: metadataKey) else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No cached version found in UserDefaults")
            return nil
        }

        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to create base directory: \(error.localizedDescription)")
            return nil
        }

        guard let fileURLs = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to read directory contents")
            return nil
        }

        let scriptlets = fileURLs.compactMap { url -> Scriptlet? in
            guard url.pathExtension == "js",
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            let name = url.deletingPathExtension().lastPathComponent
            return Scriptlet(name: name, content: data)
        }

        guard !scriptlets.isEmpty else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlet files found in cache directory")
            return nil
        }

        Logger.webExtensions.info("[Scriptlets] ✅ Loaded \(scriptlets.count) scriptlet(s) from cache v\(version)")
        return CachedScriptlets(version: version, scriptlets: scriptlets)
    }

    public func save(_ scriptlets: [Scriptlet], version: String) throws {
        Logger.webExtensions.debug("[Scriptlets] 💾 Saving \(scriptlets.count) scriptlet(s) v\(version)")
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        Logger.webExtensions.debug("[Scriptlets] 📝 Writing scriptlets to temporary directory")
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)

        for scriptlet in scriptlets {
            let file = tempDirectory.appendingPathComponent(scriptlet.fileName)
            try scriptlet.content.write(to: file, options: .atomic)
        }

        let backupDirectory = baseDirectory.appendingPathExtension("backup")

        Logger.webExtensions.debug("[Scriptlets] 🔄 Creating backup and moving to final location")
        try? fileManager.removeItem(at: backupDirectory)
        try? fileManager.moveItem(at: baseDirectory, to: backupDirectory)

        do {
            try fileManager.moveItem(at: tempDirectory, to: baseDirectory)
            try? fileManager.removeItem(at: backupDirectory)
            defaults.set(version, forKey: metadataKey)
            Logger.webExtensions.info("[Scriptlets] ✅ Successfully saved \(scriptlets.count) scriptlet(s) v\(version)")
        } catch {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to save scriptlets, restoring backup: \(error.localizedDescription)")
            try? fileManager.moveItem(at: backupDirectory, to: baseDirectory)
            throw ScriptletError.storageFailed(underlying: error.localizedDescription)
        }
    }

    public func clear() {
        Logger.webExtensions.debug("[Scriptlets] 🗑️ Clearing cached scriptlets")
        try? fileManager.removeItem(at: baseDirectory)
        defaults.removeObject(forKey: metadataKey)
        Logger.webExtensions.info("[Scriptlets] ✅ Cleared scriptlet cache")
    }
}
