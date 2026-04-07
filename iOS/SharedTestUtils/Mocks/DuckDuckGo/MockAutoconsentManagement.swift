//
//  MockAutoconsentManagement.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

@MainActor
final class MockAutoconsentManagement: AutoconsentManaging {

    var sitesNotifiedCache = Set<String>()
    var detectedByPatternsCache = Set<String>()
    var detectedByBothCache = Set<String>()
    var detectedOnlyRulesCache = Set<String>()

    private(set) var firePixelCallCount = 0
    private(set) var lastFiredPixel: AutoconsentPixel?

    func firePixel(pixel: AutoconsentPixel, additionalParameters: [String: String]) {
        firePixelCallCount += 1
        lastFiredPixel = pixel
    }

    private(set) var clearCacheCallCount = 0

    func clearCache() -> Result<Void, Error> {
        clearCacheCallCount += 1
        sitesNotifiedCache.removeAll()
        detectedByPatternsCache.removeAll()
        detectedByBothCache.removeAll()
        detectedOnlyRulesCache.removeAll()
        return .success(())
    }

    private(set) var clearCacheForDomainsCallCount = 0
    private(set) var lastClearedDomains: [String]?

    func clearCache(forDomains domains: [String]) -> Result<Void, Error> {
        clearCacheForDomainsCallCount += 1
        lastClearedDomains = domains
        return .success(())
    }

}

@MainActor
final class MockAutoconsentManagementProvider: AutoconsentManagementProviding {

    private var managements: [AutoconsentContext: MockAutoconsentManagement]

    var normalManagement: MockAutoconsentManagement {
        managements[.normal]!
    }

    var fireManagement: MockAutoconsentManagement {
        managements[.fireMode]!
    }

    init(normalManagement: MockAutoconsentManagement? = nil,
         fireManagement: MockAutoconsentManagement? = nil) {
        self.managements = [
            .normal: normalManagement ?? MockAutoconsentManagement(),
            .fireMode: fireManagement ?? MockAutoconsentManagement()
        ]
    }

    func management(for context: AutoconsentContext) -> AutoconsentManaging {
        if let existing = managements[context] {
            return existing
        }
        let mock = MockAutoconsentManagement()
        managements[context] = mock
        return mock
    }

}
