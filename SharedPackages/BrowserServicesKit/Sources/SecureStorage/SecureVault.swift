//
//  SecureVault.swift
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

/// Represents a generic vault.
///
/// To build a feature-specific vault, you should define a new protocol and conform it to this protocol. For example, `protocol SomeFeatureVault: SecureVault`.
/// Note that this protocol has an associated type for its database provider, since the provider may change in cases where you provide a mock database provider over a concrete one.
public protocol SecureVault {

    associatedtype DatabaseProvider: SecureStorageDatabaseProvider

    init(providers: SecureStorageProviders<DatabaseProvider>)

}
