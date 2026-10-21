//
//  SyncableIdentitiesValidationTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

final class SyncableIdentitiesValidationTests: XCTestCase {

    var syncableIdentity: SecureVaultModels.SyncableIdentity!

    override func setUp() {
        let identity = SecureVaultModels.Identity(
            id: 1,
            title: "Profile",
            created: Date(),
            lastUpdated: Date(),
            firstName: "John",
            middleName: "Q",
            lastName: "Doe",
            birthdayDay: 1,
            birthdayMonth: 1,
            birthdayYear: 1990,
            addressStreet: "123 Main",
            addressStreet2: "Apt 4",
            addressCity: "Ducktown",
            addressProvince: "PA",
            addressPostalCode: "12345",
            addressCountryCode: "US",
            homePhone: "1234567890",
            mobilePhone: nil,
            emailAddress: "john@example.com"
        )
        syncableIdentity = SecureVaultModels.SyncableIdentity(identity: identity, lastModified: nil)
    }

    func testWhenIdentityFieldsPassLengthValidationThenSyncableIsInitializedWithoutThrowingErrors() throws {
        XCTAssertNoThrow(try Syncable(syncableIdentity: syncableIdentity, encryptedUsing: { $0 }))
    }

    func testWhenTitleIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.title = String(repeating: "x", count: 3001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenFirstNameIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.firstName = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenMiddleNameIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.middleName = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenLastNameIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.lastName = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenBirthdayIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.birthdayDay = 1
        syncableIdentity.identity?.birthdayMonth = 1
        syncableIdentity.identity?.birthdayYear = 1990

        XCTAssertThrowsError(
            try Syncable(syncableIdentity: syncableIdentity, encryptedUsing: { value in
                if value == "1990-01-01" {
                    return String(repeating: "x", count: 101)
                }
                return value
            })
        ) { error in
            guard case Syncable.SyncableIdentityError.validationFailed = error else {
                XCTFail("unexpected error thrown: \(error)")
                return
            }
        }
    }

    func testWhenAddressStreetIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.addressStreet = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAddressStreet2IsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.addressStreet2 = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAddressCityIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.addressCity = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAddressProvinceIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.addressProvince = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAddressPostalCodeIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.addressPostalCode = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenAddressCountryCodeIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.addressCountryCode = String(repeating: "x", count: 101)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenPhoneIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.homePhone = String(repeating: "x", count: 501)
        assertSyncableInitializerThrowsValidationError()
    }

    func testWhenEmailAddressIsTooLongThenSyncableInitializerThrowsError() throws {
        syncableIdentity.identity?.emailAddress = String(repeating: "x", count: 1001)
        assertSyncableInitializerThrowsValidationError()
    }

    private func assertSyncableInitializerThrowsValidationError(file: StaticString = #file, line: UInt = #line) {
        XCTAssertThrowsError(
            try Syncable(syncableIdentity: syncableIdentity, encryptedUsing: { $0 }),
            file: file,
            line: line
        ) { error in
            guard case Syncable.SyncableIdentityError.validationFailed = error else {
                XCTFail("unexpected error thrown: \(error)", file: file, line: line)
                return
            }
        }
    }
}
