//
//  NetworkProtectionNotificationsPresenter.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

/// Abstracts the notification presentation.
///
public protocol NetworkProtectionNotificationsPresenter {

    /// Present a "connected" notification to the user.
    func showConnectedNotification(serverLocation: String?, snoozeEnded: Bool)

    /// Present a "reconnecting" notification to the user.
    func showReconnectingNotification()

    /// Present a "connection failure" notification to the user.
    func showConnectionFailureNotification()

    /// Present a "snoozing" notification to the user.
    func showSnoozingNotification(duration: TimeInterval)

    /// Present a "Superseded by another App" notification to the user.
    func showSupersededNotification()

    /// Present a test notification, triggered by the Debug menu in the app.
    /// This is never visible to end users.
    func showTestNotification()

    /// Present a "expired subscription" notification to the user.
    func showEntitlementNotification()

}
