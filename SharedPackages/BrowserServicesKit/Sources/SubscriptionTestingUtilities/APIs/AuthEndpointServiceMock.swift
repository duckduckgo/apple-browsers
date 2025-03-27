//
//  AuthEndpointServiceMock.swift
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
import Subscription

public final class AuthEndpointServiceMock: AuthEndpointService {
    public var getAccessTokenResult: Result<AccessTokenResponse, APIServiceError>?
    public var validateTokenResult: Result<ValidateTokenResponse, APIServiceError>?
    public var createAccountResult: Result<CreateAccountResponse, APIServiceError>?
    public var storeLoginResult: Result<StoreLoginResponse, APIServiceError>?

    public var onValidateToken: ((String) -> Void)?

    public var getAccessTokenCalled: Bool = false
    public var validateTokenCalled: Bool = false
    public var createAccountCalled: Bool = false
    public var storeLoginCalled: Bool = false

    public init() { }

    public func getAccessToken(token: String) async -> Result<AccessTokenResponse, APIServiceError> {
        getAccessTokenCalled = true
        return getAccessTokenResult!
    }

    public func validateToken(accessToken: String) async -> Result<ValidateTokenResponse, APIServiceError> {
        validateTokenCalled = true
        onValidateToken?(accessToken)
        return validateTokenResult!
    }

    public func createAccount(emailAccessToken: String?) async -> Result<CreateAccountResponse, APIServiceError> {
        createAccountCalled = true
        return createAccountResult!
    }

    public func storeLogin(signature: String) async -> Result<StoreLoginResponse, APIServiceError> {
        storeLoginCalled = true
        return storeLoginResult!
    }
}
