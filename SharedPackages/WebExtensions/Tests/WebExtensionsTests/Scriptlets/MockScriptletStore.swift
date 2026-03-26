//
//  MockScriptletStore.swift
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

final class MockScriptletStore: ScriptletStoring {

    var cachedScriptlets: CachedScriptlets?
    var savedFetched: [FetchedScriptlet]?
    var savedVersion: String?
    var savedExtensionType: DuckDuckGoWebExtensionType?
    var scriptletsToReturn: [Scriptlet] = []
    var clearCallCount = 0
    var clearedExtensionType: DuckDuckGoWebExtensionType?

    var cacheRootDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mock-cache")
    }

    func loadCached(for extensionType: DuckDuckGoWebExtensionType) -> CachedScriptlets? {
        cachedScriptlets
    }

    @discardableResult
    func save(_ fetched: [FetchedScriptlet], version: String, for extensionType: DuckDuckGoWebExtensionType) throws -> [Scriptlet] {
        savedFetched = fetched
        savedVersion = version
        savedExtensionType = extensionType
        return scriptletsToReturn
    }

    func clear(for extensionType: DuckDuckGoWebExtensionType) {
        clearCallCount += 1
        clearedExtensionType = extensionType
        cachedScriptlets = nil
    }

    var clearAllCallCount = 0

    func clearAll() {
        clearAllCallCount += 1
        cachedScriptlets = nil
    }
}
