//
//  PromoInitiated.swift
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

/// How a promo is initiated.
enum PromoInitiated {
    /// Initiated by the app automatically
    case app
    /// Initiated by a user action
    case user

    /// Minimum interval between showing promos of this initiation type ("global cooldown")
    var cooldown: TimeInterval {
        switch self {
        case .app: return .day
        case .user: return .hours(1)
        }
    }
}
