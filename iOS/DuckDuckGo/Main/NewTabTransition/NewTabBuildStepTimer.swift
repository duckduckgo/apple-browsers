//
//  NewTabBuildStepTimer.swift
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

import QuartzCore
import os

/// Debug only: logs how long each step of building a new tab takes.
struct NewTabBuildStepTimer {

    private static let logger = Logger(subsystem: "com.duckduckgo.mobile.ios", category: "NewTabTransition")

    private var lastMark = CACurrentMediaTime()

    mutating func mark(_ step: String) {
        let now = CACurrentMediaTime()
        let ms = (now - lastMark) * 1000
        lastMark = now
        Self.logger.debug("Build step \(step, privacy: .public): \(String(format: "%.1f", ms), privacy: .public) ms")
    }
}
