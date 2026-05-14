//
//  BrokerProfileJobEventsHandler.swift
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
import DataBrokerProtectionCore

public class BrokerProfileJobEventsHandler: EventMapping<JobEvent> {

    private let userNotificationService: DataBrokerProtectionUserNotificationService
    private let freemiumUserStateManager: FreemiumDBPUserStateManaging

    public init(
        userNotificationService: DataBrokerProtectionUserNotificationService,
        freemiumUserStateManager: FreemiumDBPUserStateManaging
    ) {
        self.userNotificationService = userNotificationService
        self.freemiumUserStateManager = freemiumUserStateManager
        super.init { event, _, _, onComplete in
            switch event {
            case .profileSaved:
                userNotificationService.resetFirstScanCompletedNotificationState()
                userNotificationService.requestNotificationPermission()
                Task {
                    await freemiumUserStateManager.recordProfileSavedIfNeeded()
                    onComplete(nil)
                }
            case .firstScanCompleted:
                userNotificationService.sendFirstScanCompletedNotification()
                onComplete(nil)
            case .firstScanCompletedAndMatchesFound:
                userNotificationService.scheduleCheckInNotificationIfPossible()
                onComplete(nil)
            case .firstProfileRemoved:
                userNotificationService.sendFirstRemovedNotificationIfPossible()
                onComplete(nil)
            case .allProfilesRemoved:
                userNotificationService.sendAllInfoRemovedNotificationIfPossible()
                onComplete(nil)
            }
        }
    }

    override init(mapping: @escaping EventMapping<JobEvent>.Mapping) {
        fatalError("Use init(userNotificationService:freemiumUserStateManager:)")
    }
}
