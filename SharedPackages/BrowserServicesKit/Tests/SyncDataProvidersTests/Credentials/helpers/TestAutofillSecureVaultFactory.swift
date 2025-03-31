//
//  TestAutofillSecureVaultFactory.swift
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

import BrowserServicesKit
import Foundation
import SecureStorage
import SecureStorageTestsUtils

extension AutofillVaultFactory {
    static func testFactory(databaseProvider: DefaultAutofillDatabaseProvider) -> AutofillVaultFactory {
        AutofillVaultFactory(makeCryptoProvider: {
            NoOpCryptoProvider()
        }, makeKeyStoreProvider: { _ in
            let provider = MockKeystoreProvider()
            provider._l1Key = "l1".data(using: .utf8)
            provider._encryptedL2Key = "encrypted".data(using: .utf8)
            return provider
        }, makeDatabaseProvider: { _ in
            databaseProvider
        })
    }
}
