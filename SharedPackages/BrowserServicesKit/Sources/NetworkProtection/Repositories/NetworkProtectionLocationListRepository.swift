//
//  NetworkProtectionLocationListRepository.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import Networking

public enum NetworkProtectionLocationListCachePolicy {
    case returnCacheElseLoad
    case ignoreCache

    static var `default` = NetworkProtectionLocationListCachePolicy.returnCacheElseLoad
}

public protocol NetworkProtectionLocationListRepository {
    func fetchLocationList() async throws -> [NetworkProtectionLocation]
    func fetchLocationList(cachePolicy: NetworkProtectionLocationListCachePolicy) async throws -> [NetworkProtectionLocation]
}

final public class NetworkProtectionLocationListCompositeRepository: NetworkProtectionLocationListRepository {
    @MainActor private static var locationList: [NetworkProtectionLocation] = []
    @MainActor private static var cacheTimestamp = Date()
    private static let cacheValidity = TimeInterval(60) // Refreshes at most once per minute
    private let client: NetworkProtectionClient
    private let tokenHandler: any SubscriptionTokenHandling
    private let errorEvents: EventMapping<NetworkProtectionError>

    convenience public init(environment: VPNSettings.SelectedEnvironment,
                            tokenHandler: any SubscriptionTokenHandling,
                            errorEvents: EventMapping<NetworkProtectionError>) {
        self.init(
            client: NetworkProtectionBackendClient(environment: environment),
            tokenHandler: tokenHandler,
            errorEvents: errorEvents
        )
    }

    init(client: NetworkProtectionClient,
         tokenHandler: any SubscriptionTokenHandling,
         errorEvents: EventMapping<NetworkProtectionError>) {
        self.client = client
        self.tokenHandler = tokenHandler
        self.errorEvents = errorEvents
    }

    @MainActor
    @discardableResult
    public func fetchLocationList(cachePolicy: NetworkProtectionLocationListCachePolicy) async throws -> [NetworkProtectionLocation] {
        switch cachePolicy {
        case .returnCacheElseLoad:
            return try await fetchLocationList()
        case .ignoreCache:
            return try await fetchLocationListFromRemote()
        }
    }

    @MainActor
    @discardableResult
    public func fetchLocationList() async throws -> [NetworkProtectionLocation] {
        try await fetchLocationListReturningCacheElseLoad()
    }

    @MainActor
    @discardableResult
    func fetchLocationListReturningCacheElseLoad() async throws -> [NetworkProtectionLocation] {
        guard !canUseCache else {
            return Self.locationList
        }
        return try await fetchLocationListFromRemote()
    }

    @MainActor
    @discardableResult
    func fetchLocationListFromRemote() async throws -> [NetworkProtectionLocation] {
        do {
            guard let authToken = try? await VPNAuthTokenBuilder.getVPNAuthToken(from: tokenHandler) else {
                throw NetworkProtectionError.noAuthTokenFound
            }
            Self.locationList = try await client.getLocations(authToken: authToken).get()
            Self.cacheTimestamp = Date()
        } catch let error as NetworkProtectionErrorConvertible {
            errorEvents.fire(error.networkProtectionError)
            throw error.networkProtectionError
        } catch let error as NetworkProtectionError {
            errorEvents.fire(error)
            throw error
        } catch {
            let unhandledError = NetworkProtectionError.unhandledError(function: #function, line: #line, error: error)
            errorEvents.fire(unhandledError)
            throw unhandledError
        }
        return Self.locationList
    }

    @MainActor
    private var canUseCache: Bool {
        !Self.locationList.isEmpty && Date().timeIntervalSince(Self.cacheTimestamp) < Self.cacheValidity
    }

    @MainActor
    public static func clearCache() {
        locationList = []
    }
}
