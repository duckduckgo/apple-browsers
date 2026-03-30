//
//  MockScriptletInstaller.swift
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
@testable import WebExtensions

final class MockScriptletInstaller: ScriptletInstalling {

    var installCallCount = 0
    var lastInstalledScriptlets: [Scriptlet]?
    var lastCacheRootDirectory: URL?
    var lastInstallationDirectory: URL?
    var shouldThrowError = false

    var allInstalledScriptlets: [[Scriptlet]] = []

    private var shouldBlock = false
    private var blockContinuation: CheckedContinuation<Void, Never>?

    var onInstallStarted: (() -> Void)?

    func installScriptlets(_ scriptlets: [Scriptlet], cacheRootDirectory: URL, to installationDirectory: URL) async throws {
        installCallCount += 1
        lastInstalledScriptlets = scriptlets
        lastCacheRootDirectory = cacheRootDirectory
        lastInstallationDirectory = installationDirectory
        allInstalledScriptlets.append(scriptlets)

        onInstallStarted?()

        if shouldBlock {
            shouldBlock = false
            await withCheckedContinuation { continuation in
                self.blockContinuation = continuation
            }
        }

        if shouldThrowError {
            throw NSError(domain: "MockScriptletInstaller", code: 1)
        }
    }

    func blockNextInstall() {
        shouldBlock = true
    }

    func resumeInstall() {
        blockContinuation?.resume()
        blockContinuation = nil
    }
}
