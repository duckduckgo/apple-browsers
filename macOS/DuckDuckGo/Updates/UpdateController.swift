//
//  UpdateController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Combine
import AppKit

protocol UpdateController: AnyObject {

    // Core update state - shared by both implementations
    var latestUpdate: Update? { get }
    var latestUpdatePublisher: Published<Update?>.Publisher { get }

    var hasPendingUpdate: Bool { get }
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { get }

    var needsNotificationDot: Bool { get set }
    var notificationDotPublisher: AnyPublisher<Bool, Never> { get }

    var lastUpdateCheckDate: Date? { get }
    var lastUpdateNotificationShownDate: Date { get set }

    var updateProgress: UpdateCycleProgress { get }
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { get }

    var areAutomaticUpdatesEnabled: Bool { get set }

    var notificationPresenter: UpdateNotificationPresenter { get }

    func runUpdate()
    func checkForUpdate()
    func openUpdatesPage()
}

extension UpdateController {

    private var shouldShowUpdateNotification: Bool {
        Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
    }

    func showUpdateNotificationIfNeeded() {
        guard let latestUpdate, hasPendingUpdate, shouldShowUpdateNotification else { return }

        let action = areAutomaticUpdatesEnabled ? UserText.autoUpdateAction : UserText.manualUpdateAction

        switch latestUpdate.type {
        case .critical:
            notificationPresenter.showUpdateNotification(
                icon: NSImage.criticalUpdateNotificationInfo,
                text: "\(UserText.criticalUpdateNotification) \(action)",
                presentMultiline: true
            )
        case .regular:
            notificationPresenter.showUpdateNotification(
                icon: NSImage.updateNotificationInfo,
                text: "\(UserText.updateAvailableNotification) \(action)",
                presentMultiline: true
            )
        }

        lastUpdateNotificationShownDate = Date()
    }
}
