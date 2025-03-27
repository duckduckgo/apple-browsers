//
//  SyncableCredentialsValidationTests.swift
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

import XCTest
import Common
import DDGSync
@testable import BrowserServicesKit
@testable import SyncDataProviders

final class SyncableCredentialsValidationTests: XCTestCase {

    var syncableCredentials: SecureVaultModels.SyncableCredentials!

    override func setUp() {
        let account = SecureVaultModels.WebsiteAccount(title: "title", username: "username", domain: "domain.com", notes: "some notes")
        let password = "secret".data(using: .utf8)
        let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: password)
        syncableCredentials = SecureVaultModels.SyncableCredentials(credentials: credentials)
    }

    func testWhenCredentialsFieldsPassLengthValidationThenSyncableIsInitializedWithoutThrowingErrors() throws {
        XCTAssertNoThrow(try Syncable(syncableCredentials: syncableCredentials, encryptedUsing: { $0 }))
    }

    func testWhenAccountTitleIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableCredentials.account?.title = String(repeating: "x", count: 10000)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAccountUsernameIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableCredentials.account?.username = String(repeating: "x", count: 10000)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAccountDomainIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableCredentials.account?.domain = String(repeating: "x", count: 10000)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAccountNotesIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableCredentials.account?.notes = String(repeating: "x", count: 10000)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenPasswordIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableCredentials.credentials?.password = String(repeating: "x", count: 10000).data(using: .utf8)
        assertSyncableInitializerThrowsValidationError()
    }

    private func assertSyncableInitializerThrowsValidationError(file: StaticString = #file, line: UInt = #line) {
        XCTAssertThrowsError(
            try Syncable(syncableCredentials: syncableCredentials, encryptedUsing: { $0 }),
            file: file,
            line: line
        ) { error in
            guard case Syncable.SyncableCredentialError.validationFailed = error else {
                XCTFail("unexpected error thrown: \(error)", file: file, line: line)
                return
            }
        }
    }
}
