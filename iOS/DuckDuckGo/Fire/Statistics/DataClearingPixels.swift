//
//  DataClearingPixels.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import PixelKit

enum DataClearingPixels {

    /// Fire button retriggered within 20 seconds
    case retriggerIn20s

    /// User performed action before data clearing completed
    case userActionBeforeCompletion
}

// MARK: - PixelKitEvent Protocol

extension DataClearingPixels: PixelKitEvent {

    var name: String {
        switch self {
        case .retriggerIn20s:
            return "m_fire_retrigger_in_20s"
        case .userActionBeforeCompletion:
            return "m_fire_user_action_before_completion"
        }
    }

    var parameters: [String: String]? {
        return nil
    }

    var error: NSError? {
        return nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}
