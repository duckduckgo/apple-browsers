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

    private let extensionsBaseDirectory: URL
    private let fileManager: FileManager
    private let scriptletsSubpath = "scriptlets"

    public init(
        extensionsBaseDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.extensionsBaseDirectory = extensionsBaseDirectory
        self.fileManager = fileManager
    }

    public func installScriptlets(_ scriptlets: [Scriptlet], to extensionID: String) async throws {
        Logger.webExtensions.debug("[Scriptlets] 📦 Installing \(scriptlets.count) scriptlet(s) to extension '\(extensionID)'")
        let targetDirectory = scriptletsDirectory(for: extensionID)

        Logger.webExtensions.debug("[Scriptlets] 🗂️ Preparing directory: \(targetDirectory.path)")
        try prepareDirectory(targetDirectory)

        for scriptlet in scriptlets {
            let targetFile = targetDirectory.appendingPathComponent(scriptlet.fileName)
            Logger.webExtensions.debug("[Scriptlets] 💾 Writing scriptlet '\(scriptlet.name)' to \(scriptlet.fileName)")
            try scriptlet.content.write(to: targetFile, options: .atomic)
        }

        Logger.webExtensions.info("[Scriptlets] ✅ Successfully installed \(scriptlets.count) scriptlet(s) to '\(extensionID)'")
    }

    public func removeScriptlets(from extensionID: String) throws {
        Logger.webExtensions.debug("[Scriptlets] 🗑️ Removing scriptlets from extension '\(extensionID)'")
        let targetDirectory = scriptletsDirectory(for: extensionID)
        try? fileManager.removeItem(at: targetDirectory)
        Logger.webExtensions.info("[Scriptlets] ✅ Removed scriptlets from '\(extensionID)'")
    }

    private func scriptletsDirectory(for extensionID: String) -> URL {
        extensionsBaseDirectory
            .appendingPathComponent(extensionID)
            .appendingPathComponent(scriptletsSubpath)
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
