//
//  SERPSettingsError.swift
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

import Foundation

/// Errors that can occur during SERP (Search Engine Results Page) settings operations.
///
/// These errors are reported through the EventMapping system to track failures
/// in settings storage and retrieval operations.
public enum SERPSettingsError: Error {

    /// Failed to serialize settings dictionary to JSON data.
    ///
    /// This error occurs when `JSONSerialization.data()` fails, typically due to
    /// non-JSON-serializable values in the settings dictionary.
    case serializationFailed

    /// Failed to read settings from the key-value store.
    ///
    /// This error occurs when the underlying storage mechanism fails during a read operation,
    /// such as keychain access failures or file system errors.
    case keyValueStoreReadError

    /// Failed to write settings to the key-value store.
    ///
    /// This error occurs when the underlying storage mechanism fails during a write operation,
    /// such as insufficient permissions, disk full, or keychain access failures.
    case keyValueStoreWriteError
}
