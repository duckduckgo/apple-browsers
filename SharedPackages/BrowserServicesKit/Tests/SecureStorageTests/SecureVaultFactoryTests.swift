//
//  SecureVaultFactoryTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import XCTest
import GRDB
import SecureStorage
import SecureStorageTestsUtils

let MockSecureVaultFactory = SecureVaultFactory<ConcreteMockSecureVault>(
    makeCryptoProvider: {
        let provider = MockCryptoProvider()
        provider._derivedKey = "derived".data(using: .utf8)
        return provider
    }, makeKeyStoreProvider: { _ in
        let provider = MockKeystoreProvider()
        provider._l1Key = "key".data(using: .utf8)
        return provider
    }, makeDatabaseProvider: { key, _ in
        return try ConcreteMockDatabaseProvider(key: key)
    }
)

// MARK: - Tests

final class MockVaultTests: XCTestCase {

    func testCreatingMockVaultWithSecureVaultFactory() throws {
        let vault = try MockSecureVaultFactory.makeVault(reporter: nil)
        let storedString = "hello, world!"

        try vault.storeSomeData(string: storedString)
        XCTAssertEqual(try vault.getStoredData(), storedString)
    }

}
