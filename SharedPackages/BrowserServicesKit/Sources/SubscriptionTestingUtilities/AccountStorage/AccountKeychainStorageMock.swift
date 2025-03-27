//
//  AccountKeychainStorageMock.swift
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

public final class AccountKeychainStorageMock: AccountStoring {
    public var authToken: String?
    public var email: String?
    public var externalID: String?

    public var mockedAccessError: AccountKeychainAccessError?

    public var clearAuthenticationStateCalled: Bool = false

    public init() { }

    public func getAuthToken() throws -> String? {
        if let mockedAccessError { throw mockedAccessError }
        return authToken
    }

    public func store(authToken: String) throws {
        if let mockedAccessError { throw mockedAccessError }
        self.authToken = authToken
    }

    public func getEmail() throws -> String? {
        if let mockedAccessError { throw mockedAccessError }
        return email
    }

    public func store(email: String?) throws {
        if let mockedAccessError { throw mockedAccessError }
        self.email = email
    }

    public func getExternalID() throws -> String? {
        if let mockedAccessError { throw mockedAccessError }
        return externalID
    }

    public func store(externalID: String?) throws {
        if let mockedAccessError { throw mockedAccessError }
        self.externalID = externalID
    }

    public func clearAuthenticationState() throws {
        clearAuthenticationStateCalled = true

        authToken = nil
        email = nil
        externalID = nil
    }
}
