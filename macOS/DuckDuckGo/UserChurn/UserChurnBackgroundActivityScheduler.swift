//
//  UserChurnBackgroundActivityScheduler.swift
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

final class UserChurnBackgroundActivityScheduler {

    private let activity: NSBackgroundActivityScheduler
    private let identifier = "com.duckduckgo.macos.browser.user-churn-scheduler"

    private let userChurnService: UserChurnService

    init(userChurnService: UserChurnService) {
        self.userChurnService = userChurnService
        activity = NSBackgroundActivityScheduler(identifier: identifier)
        activity.repeats = true
        activity.interval = 24 * 60 * 60  // Daily (in seconds)
        activity.tolerance = 4 * 60 * 60  // 4 hour tolerance
        activity.qualityOfService = .utility
    }

    func start() {
        userChurnService.checkForDefaultBrowserChange()
        activity.schedule { [weak self] completion in
            self?.userChurnService.checkForDefaultBrowserChange()
            completion(.finished)
        }
    }
}
