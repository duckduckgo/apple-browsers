//
//  MockWebsiteDataManager.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import WebKit
import WKAbstractions
import PixelKit

@testable import Core

class MockWebsiteDataManager: WebsiteDataManaging {
    private(set) var clearCallCount = 0
    private(set) var clearWithDomainsCallCount = 0
    private(set) var clearCalledWithDomains: [String]?

    func removeCookies(forDomains domains: [String], fromDataStore: any DDGWebsiteDataStore) async {}
    
    func consumeCookies(into httpCookieStore: any DDGHTTPCookieStore) async {}
    
    func clear(dataStore: any DDGWebsiteDataStore) async -> WebsiteDataClearingResult {
        clearCallCount += 1
        return makeMockResult(includeContainerCleanup: true)
    }

    func clear(dataStore: any DDGWebsiteDataStore, forDomains domains: [String]) async -> WebsiteDataClearingResult {
        clearWithDomainsCallCount += 1
        clearCalledWithDomains = domains
        return makeMockResult(includeContainerCleanup: false)
    }

    private func makeMockResult(includeContainerCleanup: Bool) -> WebsiteDataClearingResult {
        let mockInterval = WideEvent.MeasuredInterval(start: Date(), end: Date())
        let mockActionResult = ActionResult(result: .success(()), measuredInterval: mockInterval)
        return WebsiteDataClearingResult(
            safelyRemovableData: mockActionResult,
            fireproofableData: mockActionResult,
            cookies: mockActionResult,
            observationsData: mockActionResult,
            removeAllContainersAfterDelay: includeContainerCleanup ? mockActionResult : nil
        )
    }

}
