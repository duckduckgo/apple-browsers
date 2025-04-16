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

    var mockReadError: SyncError?
    var mockWriteError: SyncError?

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
    }

}
