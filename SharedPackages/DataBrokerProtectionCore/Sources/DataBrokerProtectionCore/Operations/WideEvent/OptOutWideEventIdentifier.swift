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
import PixelKit

/// We want a stable ID for different opt-out attempts associated with an extracted profile,
/// so we can measure the time spent to successfully submit/confirm an opt-out request
struct OptOutWideEventIdentifier {
    let profileIdentifier: String?
    let brokerId: Int64
    let profileQueryId: Int64
    let extractedProfileId: Int64

    /// Ideally we use the profile identifier on the broker (which falls back to the profile URL),
    /// but we need another fallback in case it's nil, so that we won't under count wide events
    ///
    /// These only need to be locally unique as they aren't sent with the wide events.
    var toGlobalId: String {
        profileIdentifier?.sha256 ?? "\(brokerId)-\(profileQueryId)-\(extractedProfileId)"
    }
}
