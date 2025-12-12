//
//  OAuthRequestError.swift
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
import Common

public enum OAuthRequestError: DDGError {
    case invalidAuthorizationRequest(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case authorizeFailed(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case invalidRequest(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case accountCreateFailed(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case invalidEmailAddress(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case invalidSessionId(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case suspendedAccount(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case emailSendingError(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case invalidLoginCredentials(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case unknownAccount(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case invalidTokenRequest(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case unverifiedAccount(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case emailAddressNotChanged(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case failedMxCheck(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case accountEditFailed(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case invalidLinkSignature(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case accountChangeEmailAddressFailed(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case invalidToken(bodyErrorCode: OAuthRequest.BodyErrorCode)
    case expiredToken(bodyErrorCode: OAuthRequest.BodyErrorCode)

    public init(from bodyErrorCode: OAuthRequest.BodyErrorCode) {
        switch bodyErrorCode {
        case .invalidAuthorizationRequest:
            self = .invalidAuthorizationRequest(bodyErrorCode: bodyErrorCode)
        case .authorizeFailed:
            self = .authorizeFailed(bodyErrorCode: bodyErrorCode)
        case .invalidRequest:
            self = .invalidRequest(bodyErrorCode: bodyErrorCode)
        case .accountCreateFailed:
            self = .accountCreateFailed(bodyErrorCode: bodyErrorCode)
        case .invalidEmailAddress:
            self = .invalidEmailAddress(bodyErrorCode: bodyErrorCode)
        case .invalidSessionId:
            self = .invalidSessionId(bodyErrorCode: bodyErrorCode)
        case .suspendedAccount:
            self = .suspendedAccount(bodyErrorCode: bodyErrorCode)
        case .emailSendingError:
            self = .emailSendingError(bodyErrorCode: bodyErrorCode)
        case .invalidLoginCredentials:
            self = .invalidLoginCredentials(bodyErrorCode: bodyErrorCode)
        case .unknownAccount:
            self = .unknownAccount(bodyErrorCode: bodyErrorCode)
        case .invalidTokenRequest:
            self = .invalidTokenRequest(bodyErrorCode: bodyErrorCode)
        case .unverifiedAccount:
            self = .unverifiedAccount(bodyErrorCode: bodyErrorCode)
        case .emailAddressNotChanged:
            self = .emailAddressNotChanged(bodyErrorCode: bodyErrorCode)
        case .failedMxCheck:
            self = .failedMxCheck(bodyErrorCode: bodyErrorCode)
        case .accountEditFailed:
            self = .accountEditFailed(bodyErrorCode: bodyErrorCode)
        case .invalidLinkSignature:
            self = .invalidLinkSignature(bodyErrorCode: bodyErrorCode)
        case .accountChangeEmailAddressFailed:
            self = .accountChangeEmailAddressFailed(bodyErrorCode: bodyErrorCode)
        case .invalidToken:
            self = .invalidToken(bodyErrorCode: bodyErrorCode)
        case .expiredToken:
            self = .expiredToken(bodyErrorCode: bodyErrorCode)
        }
    }

    public var bodyErrorCode: OAuthRequest.BodyErrorCode {
        switch self {
        case .invalidAuthorizationRequest(let bodyErrorCode),
             .authorizeFailed(let bodyErrorCode),
             .invalidRequest(let bodyErrorCode),
             .accountCreateFailed(let bodyErrorCode),
             .invalidEmailAddress(let bodyErrorCode),
             .invalidSessionId(let bodyErrorCode),
             .suspendedAccount(let bodyErrorCode),
             .emailSendingError(let bodyErrorCode),
             .invalidLoginCredentials(let bodyErrorCode),
             .unknownAccount(let bodyErrorCode),
             .invalidTokenRequest(let bodyErrorCode),
             .unverifiedAccount(let bodyErrorCode),
             .emailAddressNotChanged(let bodyErrorCode),
             .failedMxCheck(let bodyErrorCode),
             .accountEditFailed(let bodyErrorCode),
             .invalidLinkSignature(let bodyErrorCode),
             .accountChangeEmailAddressFailed(let bodyErrorCode),
             .invalidToken(let bodyErrorCode),
             .expiredToken(let bodyErrorCode):
            return bodyErrorCode
        }
    }

    public static var errorDomain: String { "com.duckduckgo.OAuthRequestError" }

    public var errorCode: Int {
        switch self {
        case .invalidAuthorizationRequest:
            return 11700
        case .authorizeFailed:
            return 11701
        case .invalidRequest:
            return 11702
        case .accountCreateFailed:
            return 11703
        case .invalidEmailAddress:
            return 11704
        case .invalidSessionId:
            return 11705
        case .suspendedAccount:
            return 11706
        case .emailSendingError:
            return 11707
        case .invalidLoginCredentials:
            return 11708
        case .unknownAccount:
            return 11709
        case .invalidTokenRequest:
            return 11710
        case .unverifiedAccount:
            return 11711
        case .emailAddressNotChanged:
            return 11712
        case .failedMxCheck:
            return 11713
        case .accountEditFailed:
            return 11714
        case .invalidLinkSignature:
            return 11715
        case .accountChangeEmailAddressFailed:
            return 11716
        case .invalidToken:
            return 11717
        case .expiredToken:
            return 11718
        }
    }

    public var underlyingError: (any Error)? { nil }

    public var description: String {
        bodyErrorCode.description
    }
}
