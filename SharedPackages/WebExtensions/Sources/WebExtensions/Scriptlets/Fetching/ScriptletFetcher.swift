//
//  ScriptletFetcher.swift
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
import Networking
import os.log

public final class ScriptletFetcher: ScriptletFetching {

    private let apiService: APIService

    public init(apiService: APIService) {
        self.apiService = apiService
    }

    public func fetch(_ descriptors: [ScriptletDescriptor]) async throws -> [FetchedScriptlet] {
        Logger.webExtensions.debug("[Scriptlets] 📡 Fetching \(descriptors.count) scriptlet(s) in parallel")
        let results = try await withThrowingTaskGroup(of: FetchedScriptlet.self) { group in
            for descriptor in descriptors {
                group.addTask {
                    try await self.fetchSingle(descriptor)
                }
            }

            var results: [FetchedScriptlet] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        Logger.webExtensions.info("[Scriptlets] ✅ Successfully fetched \(results.count) scriptlet(s)")
        return results
    }

    private func fetchSingle(_ descriptor: ScriptletDescriptor) async throws -> FetchedScriptlet {
        Logger.webExtensions.debug("[Scriptlets] 🌐 Fetching '\(descriptor.name)' from \(descriptor.url.absoluteString)")
        guard let request = APIRequestV2(url: descriptor.url, method: .get) else {
            Logger.webExtensions.error("[Scriptlets] ❌ Failed to create request for '\(descriptor.name)'")
            throw ScriptletError.emptyResponse(name: descriptor.name)
        }

        let response = try await apiService.fetch(request: request)

        guard let data = response.data, !data.isEmpty else {
            Logger.webExtensions.error("[Scriptlets] ❌ Empty response for '\(descriptor.name)'")
            throw ScriptletError.emptyResponse(name: descriptor.name)
        }

        Logger.webExtensions.debug("[Scriptlets] ✓ Fetched '\(descriptor.name)' (\(data.count) bytes)")
        return FetchedScriptlet(descriptor: descriptor, data: data)
    }
}
