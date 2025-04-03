//
//  MockNetworkProtectionLocationListRepository.swift
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

import Foundation
@testable import NetworkProtection

final class MockNetworkProtectionLocationListRepository: NetworkProtectionLocationListRepository {
    var stubFetchLocationList: [NetworkProtectionLocation] = []
    var stubFetchLocationListError: Error?
    var spyIgnoreCache: Bool = false

    func fetchLocationList() async throws -> [NetworkProtectionLocation] {
        if let stubFetchLocationListError {
            throw stubFetchLocationListError
        }
        return stubFetchLocationList
    }

    func fetchLocationList(cachePolicy: NetworkProtectionLocationListCachePolicy) async throws -> [NetworkProtectionLocation] {
        switch cachePolicy {
        case .returnCacheElseLoad:
            return try await fetchLocationList()
        case .ignoreCache:
            return try await fetchLocationListIgnoringCache()
        }
    }

    func fetchLocationListIgnoringCache() async throws -> [NetworkProtection.NetworkProtectionLocation] {
        spyIgnoreCache = true
        return try await fetchLocationList()
    }
}

extension NetworkProtectionLocation {
    static func testData(country: String = "", cities: [City] = []) -> NetworkProtectionLocation {
        return Self(country: country, cities: cities)
    }
}

extension NetworkProtectionLocation.City {
    static func testData(name: String = "") -> NetworkProtectionLocation.City {
        Self(name: name)
    }
}
