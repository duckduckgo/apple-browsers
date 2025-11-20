//
//  SERPSettingsEventHandler.swift
//  DuckDuckGo
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

enum SERPSettingsPixel: PixelKitEvent {
    case serpSettingsSerializationFailed
    case serpSettingsKeyValueStoreReadError
    case serpSettingsKeyValueStoreWriteError
    case hideAIGeneratedImagesButtonClicked
    case openDuckAIButtonClick

    var name: String {
        switch self {
        case .serpSettingsSerializationFailed:
            return "m_serp_settings_serialization_failed"
        case .serpSettingsKeyValueStoreReadError:
            return "m_serp_settings_keyvalue_store_read_error"
        case .serpSettingsKeyValueStoreWriteError:
            return "m_serp_settings_keyvalue_store_write_error"
        case .hideAIGeneratedImagesButtonClicked:
            return "m_aichat_hide_ai_generated_images_button_clicked"
        case .openDuckAIButtonClick:
            return "m_serp_settings_open_duck_ai_button_click"
        }
    }

    var parameters: [String: String]? {
        return nil
    }
}

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
                PixelKit.fire(SERPSettingsPixel.serpSettingsSerializationFailed, frequency: .dailyAndCount)
            case .keyValueStoreReadError:
                // Fires when reading from persistent storage fails.
                PixelKit.fire(SERPSettingsPixel.serpSettingsKeyValueStoreReadError, frequency: .dailyAndCount)
            case .keyValueStoreWriteError:
                // Fires when writing to persistent storage fails.
                PixelKit.fire(SERPSettingsPixel.serpSettingsKeyValueStoreWriteError, frequency: .dailyAndCount)
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
