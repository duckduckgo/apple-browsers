//
//  MockScriptletFetcher.swift
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

final class MockScriptletFetcher: ScriptletFetching {

    var fetchCallCount = 0
    var lastFetchedDescriptors: [ScriptletDescriptor]?
    var fetchedScriptlets: [FetchedScriptlet] = []
    var shouldThrowError = false
    var onFetch: (() -> Void)?

    func fetch(_ descriptors: [ScriptletDescriptor]) async throws -> [FetchedScriptlet] {
        fetchCallCount += 1
        lastFetchedDescriptors = descriptors

        if shouldThrowError {
            onFetch?()
            throw ScriptletError.emptyResponse(name: "test")
        }

        onFetch?()
        return fetchedScriptlets
    }
}
