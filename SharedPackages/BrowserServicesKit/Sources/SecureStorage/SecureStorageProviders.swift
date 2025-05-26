//
//  SecureStorageProviders.swift
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

/// Protocols can't be nested, but classes can.  This struct provides a 'namespace' for the default implementations of the providers to keep it clean for other things going on in this library.
public struct SecureStorageProviders<DatabaseProvider: SecureStorageDatabaseProvider> {

    public var crypto: SecureStorageCryptoProvider
    public var database: DatabaseProvider
    public var keystore: SecureStorageKeyStoreProvider

    public init(crypto: SecureStorageCryptoProvider, database: DatabaseProvider, keystore: SecureStorageKeyStoreProvider) {
        self.crypto = crypto
        self.database = database
        self.keystore = keystore
    }

}
