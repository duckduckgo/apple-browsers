//
//  MockEmailManagerStorage.swift
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

import BrowserServicesKit
import Foundation

public class MockEmailManagerStorage: EmailManagerStorage {

    public var mockError: EmailKeychainAccessError?

    public var mockUsername: String?
    public var mockToken: String?
    public var mockAlias: String?
    public var mockCohort: String?
    public var mockLastUseDate: String?

    public var storeTokenCallback: ((String, String, String?) -> Void)?
    public var storeAliasCallback: ((String) -> Void)?
    public var storeLastUseDateCallback: ((String) -> Void)?
    public var deleteAliasCallback: (() -> Void)?
    public var deleteAuthenticationStateCallback: (() -> Void)?
    public var deleteWaitlistStateCallback: (() -> Void)?

    public init() {}

    public func getUsername() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockUsername
    }

    public func getToken() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockToken
    }

    public func getAlias() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockAlias
    }

    public func getCohort() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockCohort
    }

    public func getLastUseDate() throws -> String? {
        if let mockError = mockError { throw mockError }
        return mockLastUseDate
    }

    public func store(token: String, username: String, cohort: String?) throws {
        storeTokenCallback?(token, username, cohort)
    }

    public func store(alias: String) throws {
        storeAliasCallback?(alias)
    }

    public func store(lastUseDate: String) throws {
        storeLastUseDateCallback?(lastUseDate)
    }

    public func deleteAlias() {
        deleteAliasCallback?()
    }

    public func deleteAuthenticationState() {
        deleteAuthenticationStateCallback?()
    }

    public func deleteWaitlistState() {
        deleteWaitlistStateCallback?()
    }

}
