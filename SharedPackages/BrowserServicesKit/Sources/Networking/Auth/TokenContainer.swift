//
//  TokenContainer.swift
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
import JWTKit

/// Container for both access and refresh tokens
///
/// WARNING: Specialised for Privacy Pro Subscription, abstract for other use cases.
///
/// This is the object that should be stored in the keychain and used to make authenticated requests
/// The decoded tokens are used to determine the user's entitlements
/// The access token is used to make authenticated requests
/// The refresh token is used to get a new access token when the current one expires
public struct TokenContainer: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let decodedAccessToken: JWTAccessToken
    public let decodedRefreshToken: JWTRefreshToken
}

extension TokenContainer: Equatable {

    public static func == (lhs: TokenContainer, rhs: TokenContainer) -> Bool {
        lhs.accessToken == rhs.accessToken && lhs.refreshToken == rhs.refreshToken
    }
}

extension TokenContainer: CustomDebugStringConvertible {

    public var debugDescription: String {
        """
        Access Token: \(decodedAccessToken)
        Refresh Token: \(decodedRefreshToken)
        """
    }
}

/// Convenience init and accessor used when the token container is send via IPC and NSData is needed
extension TokenContainer {

    public var data: NSData? {
        return try? JSONEncoder().encode(self) as NSData
    }

    public init(with data: NSData) throws {
        self = try JSONDecoder().decode(TokenContainer.self, from: data as Data)
    }
}

public enum TokenPayloadError: Error {
    case invalidTokenScope
}

public struct JWTAccessToken: JWTPayload, Equatable {
    let exp: ExpirationClaim
    let iat: IssuedAtClaim
    let sub: SubjectClaim
    let aud: AudienceClaim
    let iss: IssuerClaim
    let jti: IDClaim
    let scope: String
    let api: String // always v2
    public let email: String?
    let entitlements: [EntitlementPayload]

    public func verify(using signer: JWTKit.JWTSigner) throws {
        try self.exp.verifyNotExpired()
        if self.scope != "privacypro" {
            throw TokenPayloadError.invalidTokenScope
        }
    }

    public func isExpired() -> Bool {
        do {
            try self.exp.verifyNotExpired()
        } catch {
            return true
        }
        return false
    }

    public var externalID: String {
        sub.value
    }

    public var expirationDate: Date {
        exp.value
    }
}

public struct JWTRefreshToken: JWTPayload, Equatable {
    let exp: ExpirationClaim
    let iat: IssuedAtClaim
    let sub: SubjectClaim
    let aud: AudienceClaim
    let iss: IssuerClaim
    let jti: IDClaim
    let scope: String
    let api: String

    public func verify(using signer: JWTKit.JWTSigner) throws {
        try self.exp.verifyNotExpired()
        if self.scope != "refresh" {
            throw TokenPayloadError.invalidTokenScope
        }
    }

    public func isExpired() -> Bool {
        do {
            try self.exp.verifyNotExpired()
        } catch {
            return true
        }
        return false
    }

    public var expirationDate: Date {
        exp.value
    }
}

public enum SubscriptionEntitlement: String, Codable, Equatable, CustomDebugStringConvertible {
    case networkProtection = "Network Protection"
    case dataBrokerProtection = "Data Broker Protection"
    case identityTheftRestoration = "Identity Theft Restoration"
    case identityTheftRestorationGlobal = "Global Identity Theft Restoration"
    case paidAIChat = "Premium DuckChat"
    case unknown

    public init(from decoder: Decoder) throws {
        self = try Self(rawValue: decoder.singleValueContainer().decode(RawValue.self)) ?? .unknown
    }

    public var debugDescription: String {
        return self.rawValue
    }

    public static func areEntitlementsEqual(_ lhs: [SubscriptionEntitlement]?, _ rhs: [SubscriptionEntitlement]?) -> Bool {
        return Set(lhs ?? []) == Set(rhs ?? [])
    }
}

public struct EntitlementPayload: Codable, Equatable {
    public let product: SubscriptionEntitlement // Can expand in future
    public let name: String // always `subscriber`
}

public extension JWTAccessToken {

    var subscriptionEntitlements: [SubscriptionEntitlement] {
        entitlements.map(\.product)
    }

    func hasEntitlement(_ entitlement: SubscriptionEntitlement) -> Bool {
        subscriptionEntitlements.contains(entitlement)
    }
}
