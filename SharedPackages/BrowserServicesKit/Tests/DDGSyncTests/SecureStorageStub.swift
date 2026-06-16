//
//  SecureStorageStub.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
@testable import DDGSync

class SecureStorageStub: SecureStoring {

    var theAccount: SyncAccount?
    var theScopedPassword: Data?
    var theProtectedKeysData: Data?

    var mockReadError: SyncError?
    var mockWriteError: SyncError?
    var persistScopedPasswordCalls: [Data] = []
    var persistScopedPasswordCalled: (() -> Void)?

    func persistAccount(_ account: SyncAccount) throws {
        if let mockWriteError {
            throw mockWriteError
        }

        theAccount = account
    }

    func account() throws -> SyncAccount? {
        if let mockReadError {
            throw mockReadError
        }
        return theAccount
    }

    func removeAccount() throws {
        theAccount = nil
        theScopedPassword = nil
        theProtectedKeysData = nil
    }

    func persistScopedPassword(_ scopedPassword: Data) throws {
        persistScopedPasswordCalls.append(scopedPassword)
        defer {
            persistScopedPasswordCalled?()
        }
        if let mockWriteError {
            throw mockWriteError
        }
        theScopedPassword = scopedPassword
    }

    func scopedPassword() throws -> Data? {
        if let mockReadError {
            throw mockReadError
        }
        return theScopedPassword
    }

    func removeScopedPassword() throws {
        theScopedPassword = nil
    }

    func persistProtectedKeys(_ data: Data) throws {
        if let mockWriteError {
            throw mockWriteError
        }
        theProtectedKeysData = data
    }

    func removeProtectedKeys() throws {
        theProtectedKeysData = nil
    }

}
