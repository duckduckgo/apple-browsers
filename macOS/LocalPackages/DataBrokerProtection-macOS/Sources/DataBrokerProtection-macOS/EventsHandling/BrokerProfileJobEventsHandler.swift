//
//  BrokerProfileJobEventsHandler.swift
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
import UserNotifications
import Common
import AppKit
import os.log
import PixelKit
import DataBrokerProtectionCore

public class BrokerProfileJobEventsHandler: EventMapping<JobEvent> {

    private let userNotificationService: DataBrokerProtectionUserNotificationService

    public init(userNotificationService: DataBrokerProtectionUserNotificationService) {
        self.userNotificationService = userNotificationService
        super.init { event, _, _, _ in
            switch event {
            case .profileSaved:
                userNotificationService.requestNotificationPermission()
            case .firstScanCompleted:
                userNotificationService.sendFirstScanCompletedNotification()
            case .firstScanCompletedAndMatchesFound:
                userNotificationService.scheduleCheckInNotificationIfPossible()
            case .firstProfileRemoved:
                userNotificationService.sendFirstRemovedNotificationIfPossible()
            case .allProfilesRemoved:
                userNotificationService.sendAllInfoRemovedNotificationIfPossible()
            }
        }
    }

    override init(mapping: @escaping EventMapping<JobEvent>.Mapping) {
        fatalError("Use init()")
    }
}
