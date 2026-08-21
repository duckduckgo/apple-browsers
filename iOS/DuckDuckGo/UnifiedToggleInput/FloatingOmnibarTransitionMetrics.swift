//
//  FloatingOmnibarTransitionMetrics.swift
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

import UIKit

enum FloatingOmnibarTransitionMetrics {

    static let legacyBottomDuration: TimeInterval = 0.35
    static let legacyTopDuration: TimeInterval = 0.25
    static let floatingDurationScale: TimeInterval = 5.0 / 16.0

    static func duration(isBottom: Bool, isFloatingUIEnabled: Bool) -> TimeInterval {
        let legacy = isBottom ? legacyBottomDuration : legacyTopDuration
        return isFloatingUIEnabled ? legacy * floatingDurationScale : legacy
    }

}
