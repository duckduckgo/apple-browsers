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
    case invalidAuthorizationRequest(bodyError: OAuthRequest.BodyError)
    case authorizeFailed(bodyError: OAuthRequest.BodyError)
    case invalidRequest(bodyError: OAuthRequest.BodyError)
    case accountCreateFailed(bodyError: OAuthRequest.BodyError)
    case invalidEmailAddress(bodyError: OAuthRequest.BodyError)
    case invalidSessionId(bodyError: OAuthRequest.BodyError)
    case suspendedAccount(bodyError: OAuthRequest.BodyError)
    case emailSendingError(bodyError: OAuthRequest.BodyError)
    case invalidLoginCredentials(bodyError: OAuthRequest.BodyError)
    case unknownAccount(bodyError: OAuthRequest.BodyError)
    case invalidTokenRequest(bodyError: OAuthRequest.BodyError)
    case unverifiedAccount(bodyError: OAuthRequest.BodyError)
    case emailAddressNotChanged(bodyError: OAuthRequest.BodyError)
    case failedMxCheck(bodyError: OAuthRequest.BodyError)
    case accountEditFailed(bodyError: OAuthRequest.BodyError)
    case invalidLinkSignature(bodyError: OAuthRequest.BodyError)
    case accountChangeEmailAddressFailed(bodyError: OAuthRequest.BodyError)
    case invalidToken(bodyError: OAuthRequest.BodyError)
    case expiredToken(bodyError: OAuthRequest.BodyError)

    public init(from bodyError: OAuthRequest.BodyError) {
        switch bodyError.errorCode {
        case .invalidAuthorizationRequest:
            self = .invalidAuthorizationRequest(bodyError: bodyError)
        case .authorizeFailed:
            self = .authorizeFailed(bodyError: bodyError)
        case .invalidRequest:
            self = .invalidRequest(bodyError: bodyError)
        case .accountCreateFailed:
            self = .accountCreateFailed(bodyError: bodyError)
        case .invalidEmailAddress:
            self = .invalidEmailAddress(bodyError: bodyError)
        case .invalidSessionId:
            self = .invalidSessionId(bodyError: bodyError)
        case .suspendedAccount:
            self = .suspendedAccount(bodyError: bodyError)
        case .emailSendingError:
            self = .emailSendingError(bodyError: bodyError)
        case .invalidLoginCredentials:
            self = .invalidLoginCredentials(bodyError: bodyError)
        case .unknownAccount:
            self = .unknownAccount(bodyError: bodyError)
        case .invalidTokenRequest:
            self = .invalidTokenRequest(bodyError: bodyError)
        case .unverifiedAccount:
            self = .unverifiedAccount(bodyError: bodyError)
        case .emailAddressNotChanged:
            self = .emailAddressNotChanged(bodyError: bodyError)
        case .failedMxCheck:
            self = .failedMxCheck(bodyError: bodyError)
        case .accountEditFailed:
            self = .accountEditFailed(bodyError: bodyError)
        case .invalidLinkSignature:
            self = .invalidLinkSignature(bodyError: bodyError)
        case .accountChangeEmailAddressFailed:
            self = .accountChangeEmailAddressFailed(bodyError: bodyError)
        case .invalidToken:
            self = .invalidToken(bodyError: bodyError)
        case .expiredToken:
            self = .expiredToken(bodyError: bodyError)
        }
    }

    public var bodyError: OAuthRequest.BodyError {
        switch self {
        case .invalidAuthorizationRequest(let bodyError),
             .authorizeFailed(let bodyError),
             .invalidRequest(let bodyError),
             .accountCreateFailed(let bodyError),
             .invalidEmailAddress(let bodyError),
             .invalidSessionId(let bodyError),
             .suspendedAccount(let bodyError),
             .emailSendingError(let bodyError),
             .invalidLoginCredentials(let bodyError),
             .unknownAccount(let bodyError),
             .invalidTokenRequest(let bodyError),
             .unverifiedAccount(let bodyError),
             .emailAddressNotChanged(let bodyError),
             .failedMxCheck(let bodyError),
             .accountEditFailed(let bodyError),
             .invalidLinkSignature(let bodyError),
             .accountChangeEmailAddressFailed(let bodyError),
             .invalidToken(let bodyError),
             .expiredToken(let bodyError):
            return bodyError
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

    public var underlyingError: (any Error)? {
        return self.bodyError.tokenStatus
    }

    public var description: String {
        bodyError.description
    }
}
