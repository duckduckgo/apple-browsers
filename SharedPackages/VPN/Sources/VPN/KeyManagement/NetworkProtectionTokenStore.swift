//
//  NetworkProtectionTokenStore.swift
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
import os.log

public protocol NetworkProtectionTokenStore {
    /// Store an auth token.
    ///
    @available(iOS, deprecated, message: "[NetP Subscription] Use subscription access token instead")
    func store(_ token: String) throws

    /// Obtain the current auth token.
    ///
    func fetchToken() async throws -> String?

    /// Delete the stored auth token.
    ///
    @available(iOS, deprecated, message: "[NetP Subscription] Use subscription access token instead")
    func deleteToken() throws
}

#if os(macOS)

/// Store an auth token for NetworkProtection on behalf of the user. This key is then used to authenticate requests for registration and server fetches from the Network Protection backend servers.
/// Writing a new auth token will replace the old one.
public final class NetworkProtectionKeychainTokenStore: NetworkProtectionTokenStore {
    private let keychainStore: NetworkProtectionKeychainStore
    private let errorEvents: EventMapping<NetworkProtectionError>?
    private let useAccessTokenProvider: Bool
    public typealias AccessTokenProvider = () -> String?
    private let accessTokenProvider: AccessTokenProvider

    public static var authTokenPrefix: String { "ddg:" }

    public struct Defaults {
        static let tokenStoreEntryLabel = "DuckDuckGo Network Protection Auth Token"
        public static let tokenStoreService = "com.duckduckgo.networkprotection.authToken"
        static let tokenStoreName = "com.duckduckgo.networkprotection.token"
    }

    /// Class initialiser
    /// - Parameters:
    ///   - keychainType: The keychain type used for fetching and storing the token.
    ///   - serviceName: The keychain service name used for fetching and storing the token.
    ///   - errorEvents: A mapper for error events.
    ///   - useAccessTokenProvider: if true the class will use the access token provider to fetch the token.
    ///   - accessTokenProvider: Defines how to actually retrieve the subscription access token.
    public init(keychainType: KeychainType,
                serviceName: String = Defaults.tokenStoreService,
                errorEvents: EventMapping<NetworkProtectionError>?,
                useAccessTokenProvider: Bool,
                accessTokenProvider: @escaping AccessTokenProvider) {
        keychainStore = NetworkProtectionKeychainStore(label: Defaults.tokenStoreEntryLabel,
                                                       serviceName: serviceName,
                                                       keychainType: keychainType)
        self.errorEvents = errorEvents
        self.useAccessTokenProvider = useAccessTokenProvider
        self.accessTokenProvider = accessTokenProvider
    }

    public func store(_ token: String) throws {
        let data = token.data(using: .utf8)!
        do {
            try keychainStore.writeData(data, named: Defaults.tokenStoreName)
        } catch {
            handle(error)
            throw error
        }
    }

    private func makeToken(from subscriptionAccessToken: String) -> String {
        Self.authTokenPrefix + subscriptionAccessToken
    }

    public func fetchToken() throws -> String? {
        if useAccessTokenProvider {
            return accessTokenProvider().map { makeToken(from: $0) }
        }

        do {
            return try keychainStore.readData(named: Defaults.tokenStoreName).flatMap {
                String(data: $0, encoding: .utf8)
            }
        } catch {
            handle(error)
            throw error
        }
    }

    public func deleteToken() throws {
        Logger.networkProtection.debug("Deleting token")
        do {
            try keychainStore.deleteData(named: Defaults.tokenStoreName)
        } catch {
            handle(error)
            throw error
        }
    }

    // MARK: - EventMapping

    private func handle(_ error: Error) {
        guard let error = error as? NetworkProtectionKeychainStoreError else {
            assertionFailure("Failed to cast Network Protection Token store error")
            Logger.networkProtection.fault("Failed to cast Network Protection Keychain store error")
            errorEvents?.fire(NetworkProtectionError.unhandledError(function: #function, line: #line, error: error))
            return
        }

        errorEvents?.fire(error.networkProtectionError)
    }
}

#else

public final class NetworkProtectionKeychainTokenStore: NetworkProtectionTokenStore {
    private let accessTokenProvider: () async -> String?

    public static var authTokenPrefix: String { "ddg:" }

    public init(accessTokenProvider: @escaping () async -> String?) {
        self.accessTokenProvider = accessTokenProvider
    }

    public func store(_ token: String) throws {
        assertionFailure("Unsupported operation")
    }

    public func fetchToken() async throws -> String? {
        await accessTokenProvider().map { makeToken(from: $0) }
    }

    public func deleteToken() throws {
        assertionFailure("Unsupported operation")
    }

    private func makeToken(from subscriptionAccessToken: String) -> String {
        Self.authTokenPrefix + subscriptionAccessToken
    }
}

#endif

// MARK: - V2

#if os(macOS)

/// Store an auth token for NetworkProtection on behalf of the user. This key is then used to authenticate requests for registration and server fetches from the Network Protection backend servers.
/// Writing a new auth token will replace the old one.
public final class NetworkProtectionKeychainTokenStoreV2: AuthTokenStoring {
    private let keychainStore: NetworkProtectionKeychainStore
    private let errorEventsHandler: EventMapping<NetworkProtectionError>?

    public struct Defaults {
        static let bundleID = Bundle.main.bundleIdentifier ?? "com.duckduckgo.networkprotection"
        static let tokenStoreEntryLabel = "DuckDuckGo Network Protection Auth Token Container"
        public static let tokenStoreService = "\(bundleID).authTokenContainer"
        static let tokenStoreName = "\(bundleID).tokenContainer"
    }

    /// - isSubscriptionEnabled: Controls whether the subscription access token is used to authenticate with the NetP backend
    /// - accessTokenProvider: Defines how to actually retrieve the subscription access token
    public init(keychainType: KeychainType,
                serviceName: String = Defaults.tokenStoreService,
                errorEventsHandler: EventMapping<NetworkProtectionError>?
    ) {
        keychainStore = NetworkProtectionKeychainStore(label: Defaults.tokenStoreEntryLabel,
                                                       serviceName: serviceName,
                                                       keychainType: keychainType)
        self.errorEventsHandler = errorEventsHandler
    }

    public func getTokenContainer() throws -> Networking.TokenContainer? {
        do {
            if let data = try keychainStore.readData(named: Defaults.tokenStoreName) as? NSData {
                return try TokenContainer(with: data)
            }
        } catch {
            handle(error)
            throw error
        }
        return nil
    }

    public func saveTokenContainer(_ tokenContainer: Networking.TokenContainer?) throws {
        do {
            guard let tokenContainer,
                  let data = tokenContainer.data as? Data else {
                try keychainStore.deleteData(named: Defaults.tokenStoreName)
                return
            }
            try keychainStore.writeData(data, named: Defaults.tokenStoreName)
        } catch {
            handle(error)
            throw error
        }
    }

    // MARK: - EventMapping

    private func handle(_ error: Error) {
        guard let error = error as? NetworkProtectionKeychainStoreError else {
            assertionFailure("Failed to cast Network Protection Token store error")
            Logger.networkProtection.fault("Failed to cast Network Protection Keychain store error")
            errorEventsHandler?.fire(NetworkProtectionError.unhandledError(function: #function, line: #line, error: error))
            return
        }

        errorEventsHandler?.fire(error.networkProtectionError)
    }
}

#else

public final class NetworkProtectionKeychainTokenStoreV2: NetworkProtectionTokenStore {
    private let accessTokenProvider: () -> String?

    public static var authTokenPrefix: String { "ddg:" }

    public init(accessTokenProvider: @escaping () -> String?) {
        self.accessTokenProvider = accessTokenProvider
    }

    public func store(_ token: String) throws {
        assertionFailure("Unsupported operation")
    }

    public func fetchToken() throws -> String? {
        accessTokenProvider().map { makeToken(from: $0) }
    }

    public func deleteToken() throws {
        assertionFailure("Unsupported operation")
    }

    private func makeToken(from subscriptionAccessToken: String) -> String {
        Self.authTokenPrefix + subscriptionAccessToken
    }
}

#endif
