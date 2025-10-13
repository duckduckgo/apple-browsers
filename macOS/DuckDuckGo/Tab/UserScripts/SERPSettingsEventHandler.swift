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

final class SERPSettingsEventHandler: EventMapping<SERPSettingsError> {

    init() {
        super.init { event, error, _, _ in
            switch event {
            case .serializationFailed:
                if let error {
                    PixelKit.fire(DebugEvent(GeneralPixel.serpSettingsSerializationFailed(error: error)), frequency: .dailyAndCount)
                }
            case .deserializationFailed:
                // Currently not used, but included for completeness
                break
            case .keyValueStoreReadError:
                if let error {
                    PixelKit.fire(DebugEvent(GeneralPixel.serpSettingsKeyValueStoreReadError(error: error)), frequency: .dailyAndCount)
                }
            case .keyValueStoreWriteError:
                if let error {
                    PixelKit.fire(DebugEvent(GeneralPixel.serpSettingsKeyValueStoreWriteError(error: error)), frequency: .dailyAndCount)
                }
            }
        }
    }

    @available(*, unavailable, message: "Use init() instead")
    override init(mapping: @escaping EventMapping<SERPSettingsError>.Mapping) {
        fatalError("Use init()")
    }
}
