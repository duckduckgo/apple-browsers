//
//  SERPSettingsEventHandler.swift
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
import Common
import PixelKit
import SERPSettings

/// macOS-specific event handler for SERP settings errors.
///
/// This class maps `SERPSettingsError` events to macOS pixel events for
/// analytics tracking. All errors are reported as debug pixels with
/// daily aggregation and individual occurrence counting.
///
/// ## Error Reporting Strategy
///
/// All pixels use the `.dailyAndCount` frequency:
/// - **Daily**: Prevents spam from repeated errors
/// - **Count**: Tracks how often each error occurs for debugging
///
/// ## Usage
///
/// ```swift
/// let handler = SERPSettingsEventHandler()
/// let provider = SERPSettingsProvider(eventMapper: handler)
/// ```
///
/// The handler is automatically invoked by `SERPSettingsProviding` when
/// storage operations fail.
final class SERPSettingsEventHandler: EventMapping<SERPSettingsError> {

    /// Creates a new SERP settings event handler with default pixel mapping.
    ///
    /// This initializer configures the event-to-pixel mappings for all
    /// supported error types.
    init() {
        super.init { event, _, _, _ in
            switch event {
            case .serializationFailed:
                // Fires when converting settings dictionary to JSON fails.
                PixelKit.fire(GeneralPixel.serpSettingsSerializationFailed, frequency: .dailyAndCount)
            case .keyValueStoreReadError:
                // Fires when reading from persistent storage fails.
                PixelKit.fire(GeneralPixel.serpSettingsKeyValueStoreReadError, frequency: .dailyAndCount)
            case .keyValueStoreWriteError:
                // Fires when writing to persistent storage fails.
                PixelKit.fire(GeneralPixel.serpSettingsKeyValueStoreWriteError, frequency: .dailyAndCount)
            }
        }
    }

    /// Prevents accidental initialization with custom mapping.
    ///
    /// This override ensures the default pixel mapping defined in `init()` is always used.
    @available(*, unavailable, message: "Use init() instead")
    override init(mapping: @escaping EventMapping<SERPSettingsError>.Mapping) {
        fatalError("Use init()")
    }
}
