//
//  NetworkProtectionError.swift
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

protocol NetworkProtectionErrorConvertible {
    var networkProtectionError: NetworkProtectionError { get }
}

public enum NetworkProtectionError: LocalizedError, CustomNSError {

    // Tunnel configuration errors
    case noServerRegistrationInfo
    case couldNotSelectClosestServer
    case couldNotGetPeerPublicKey
    case couldNotGetPeerHostName
    case couldNotGetInterfaceAddressRange

    // Client errors
    case failedToFetchServerList(Error?)
    case failedToParseServerListResponse(Error)
    case failedToFetchLocationList(Error)
    case failedToParseLocationListResponse(Error)
    case failedToFetchServerStatus(Error)
    case failedToParseServerStatusResponse(Error)
    case failedToEncodeRegisterKeyRequest
    case failedToFetchRegisteredServers(Error?)
    case failedToParseRegisteredServersResponse(Error)
    case invalidAuthToken
    case serverListInconsistency

    // Keychain errors
    case failedToCastKeychainValueToData(field: String)
    case keychainReadError(field: String, status: Int32)
    case keychainWriteError(field: String, status: Int32)
    case keychainUpdateError(field: String, status: Int32)
    case keychainDeleteError(status: Int32)

    // Wireguard errors
    case wireGuardCannotLocateTunnelFileDescriptor
    case wireGuardInvalidState(reason: String)
    case wireGuardDnsResolution
    case wireGuardSetNetworkSettings(Error)
    case startWireGuardBackend(Error)
    case setWireguardConfig(Error)

    // Auth errors
    case noAuthTokenFound

    // Subscription errors
    case vpnAccessRevoked

    // Unhandled error
    case unhandledError(function: String, line: Int, error: Error)

    public static let errorDomain = "com.duckduckgo.NetworkProtectionError.domain"

    public var errorCode: Int {
        switch self {
            // 0+ - Tunnel configuration errors
        case .noServerRegistrationInfo: return 0
        case .couldNotSelectClosestServer: return 1
        case .couldNotGetPeerPublicKey: return 2
        case .couldNotGetPeerHostName: return 3
        case .couldNotGetInterfaceAddressRange: return 4
            // 100+ - Client errors
        case .failedToFetchServerList: return 100
        case .failedToParseServerListResponse: return 101
        case .failedToFetchLocationList: return 102
        case .failedToParseLocationListResponse: return 103
        case .failedToEncodeRegisterKeyRequest: return 104
        case .failedToFetchRegisteredServers: return 105
        case .failedToParseRegisteredServersResponse: return 106
        case .invalidAuthToken: return 112
        case .serverListInconsistency: return 113
        case .failedToFetchServerStatus: return 114
        case .failedToParseServerStatusResponse: return 115
            // 200+ - Keychain errors
        case .failedToCastKeychainValueToData: return 300
        case .keychainReadError: return 201
        case .keychainWriteError: return 202
        case .keychainUpdateError: return 203
        case .keychainDeleteError: return 204
            // 300+ - Wireguard errors
        case .wireGuardCannotLocateTunnelFileDescriptor: return 300
        case .wireGuardInvalidState: return 301
        case .wireGuardDnsResolution: return 302
        case .wireGuardSetNetworkSettings: return 303
        case .startWireGuardBackend: return 304
        case .setWireguardConfig: return 305
            // 400+ Auth errors
        case .noAuthTokenFound: return 400
            // 500+ Subscription errors
        case .vpnAccessRevoked: return 500
            // 600+ Unhandled errors
        case .unhandledError: return 600
        }
    }

    public var errorUserInfo: [String: Any] {
        switch self {
        case .noServerRegistrationInfo,
                .couldNotSelectClosestServer,
                .couldNotGetPeerPublicKey,
                .couldNotGetPeerHostName,
                .couldNotGetInterfaceAddressRange,
                .failedToEncodeRegisterKeyRequest,
                .invalidAuthToken,
                .serverListInconsistency,
                .failedToCastKeychainValueToData,
                .keychainReadError,
                .keychainWriteError,
                .keychainUpdateError,
                .keychainDeleteError,
                .wireGuardCannotLocateTunnelFileDescriptor,
                .wireGuardInvalidState,
                .wireGuardDnsResolution,
                .noAuthTokenFound,
                .vpnAccessRevoked:
            return [:]
        case .failedToFetchServerList(let error),
                .failedToFetchRegisteredServers(let error):
            guard let error else {
                return [:]
            }

            return [
                NSUnderlyingErrorKey: error
            ]
        case .failedToParseServerListResponse(let error),
                .failedToFetchLocationList(let error),
                .failedToParseLocationListResponse(let error),
                .failedToParseRegisteredServersResponse(let error),
                .wireGuardSetNetworkSettings(let error),
                .startWireGuardBackend(let error),
                .setWireguardConfig(let error),
                .unhandledError(_, _, let error),
                .failedToFetchServerStatus(let error),
                .failedToParseServerStatusResponse(let error):
            return [
                NSUnderlyingErrorKey: error
            ]
        }
    }

    public var errorDescription: String? {
        // This is probably not the most elegant error to show to a user but
        // it's a great way to get detailed reports for those cases we haven't
        // provided good descriptions for yet.
        return "NetworkProtectionError.\(String(describing: self))"
    }
}
