//
//  ApplicationBuildType.swift
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

import Common
import FoundationExtensions
import Foundation

protocol ApplicationBuildType {
    var isSparkleBuild: Bool { get }
    var isAppStoreBuild: Bool { get }
    var isDebugBuild: Bool { get }
    var isReviewBuild: Bool { get }
    var isAlphaBuild: Bool { get }
}

struct StandardApplicationBuildType: ApplicationBuildType {

    let isAppStoreBuild: Bool = AppVersion.isAppStoreBuild
    var isSparkleBuild: Bool { !isAppStoreBuild }

    var isDebugBuild: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

    let isReviewBuild: Bool = Bundle.main.bundleIdentifier?.contains(".review") ?? false
    let isAlphaBuild: Bool = Bundle.main.bundleIdentifier?.contains(".alpha") ?? false

}

extension ApplicationBuildType {

    /// Returns the pixel channel name based on internal-user status and build type.
    ///
    /// - `"canary"` — internal users (logged in via the internal user flow)
    /// - `"dev"` — alpha or review builds that are not internal users
    /// - `nil` — non-internal users on production builds (channel parameter is omitted)
    func channelName(isInternalUser: Bool) -> String? {
        if isInternalUser { return "canary" }
        if isAlphaBuild || isReviewBuild { return "dev" }
        return nil
    }
}
