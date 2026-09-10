//
//  OptOutWideEventIdentifier.swift
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
import BrowserServicesKit

/// We want a stable ID for different opt-out attempts associated with an extracted profile,
/// so we can measure the time spent to successfully submit/confirm an opt-out request
struct OptOutWideEventIdentifier {
    let brokerId: Int64
    let profileQueryId: Int64
    let extractedProfileId: Int64

    /// Returns UUID-shaped string
    /// These only need to be locally unique as they aren't sent with the wide events.
    var toGlobalId: String {
        let hash = "\(brokerId)-\(profileQueryId)-\(extractedProfileId)".sha256
        return [
            String(hash.prefix(8)),
            String(hash.dropFirst(8).prefix(4)),
            String(hash.dropFirst(12).prefix(4)),
            String(hash.dropFirst(16).prefix(4)),
            String(hash.dropFirst(20).prefix(12))
        ].joined(separator: "-")
    }
}
