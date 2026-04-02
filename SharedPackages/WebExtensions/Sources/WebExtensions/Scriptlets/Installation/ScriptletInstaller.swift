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

public final class ScriptletInstaller: ScriptletInstalling {

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func installScriptlets(_ scriptlets: [Scriptlet], cacheRootDirectory: URL, to installationDirectory: URL) async throws {
        try prepareDirectory(installationDirectory)

        for scriptlet in scriptlets {
            let sourceFile = cacheRootDirectory.appendingPathComponent(scriptlet.relativeCachedPath)
            let targetFile = installationDirectory.appendingPathComponent(scriptlet.path)

            let targetFileDirectory = targetFile.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: targetFileDirectory.path) {
                try fileManager.createDirectory(at: targetFileDirectory, withIntermediateDirectories: true)
            }

            if fileManager.fileExists(atPath: targetFile.path) {
                try fileManager.removeItem(at: targetFile)
            }

            try fileManager.copyItem(at: sourceFile, to: targetFile)
        }
    }

    private func prepareDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
