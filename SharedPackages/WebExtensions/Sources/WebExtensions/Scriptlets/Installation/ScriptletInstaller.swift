//
//  ScriptletInstaller.swift
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

public final class ScriptletInstaller: ScriptletInstalling {

    private let fileManager: FileManager
    private let scriptletsSubpath = "scriptlets"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func installScriptlets(_ scriptlets: [Scriptlet], cacheRootDirectory: URL, to installationDirectory: URL) async throws {
        Logger.webExtensions.debug("[Scriptlets] 📦 Installing \(scriptlets.count) scriptlet(s) to '\(installationDirectory.path)'")
        let targetDirectory = installationDirectory.appendingPathComponent(scriptletsSubpath)

        Logger.webExtensions.debug("[Scriptlets] 🗂️ Preparing directory: \(targetDirectory.path)")
        try prepareDirectory(targetDirectory)

        for scriptlet in scriptlets {
            let sourceFile = cacheRootDirectory.appendingPathComponent(scriptlet.relativeCachedPath)
            let targetFile = targetDirectory.appendingPathComponent(scriptlet.path)

            let targetFileDirectory = targetFile.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: targetFileDirectory.path) {
                try fileManager.createDirectory(at: targetFileDirectory, withIntermediateDirectories: true)
            }

            Logger.webExtensions.debug("[Scriptlets] 📋 Copying scriptlet '\(scriptlet.relativeCachedPath)' to \(scriptlet.path)")
            try fileManager.copyItem(at: sourceFile, to: targetFile)
        }

        Logger.webExtensions.info("[Scriptlets] ✅ Successfully installed \(scriptlets.count) scriptlet(s) to '\(installationDirectory.path)'")
    }

    public func removeScriptlets(from installationDirectory: URL) throws {
        Logger.webExtensions.debug("[Scriptlets] 🗑️ Removing scriptlets from '\(installationDirectory.path)'")
        let targetDirectory = installationDirectory.appendingPathComponent(scriptletsSubpath)
        try? fileManager.removeItem(at: targetDirectory)
        Logger.webExtensions.info("[Scriptlets] ✅ Removed scriptlets from '\(installationDirectory.path)'")
    }

    private func prepareDirectory(_ directory: URL) throws {
        try? fileManager.removeItem(at: directory)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
