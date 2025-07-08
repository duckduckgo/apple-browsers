//
//  VPNNotificationsPresenterTogglableDecorator.swift
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

final public class VPNNotificationsPresenterTogglableDecorator: VPNNotificationsPresenting {
    private let settings: VPNSettings
    private let defaults: UserDefaults
    private let wrappeePresenter: VPNNotificationsPresenting

    public init(settings: VPNSettings, defaults: UserDefaults, wrappee: VPNNotificationsPresenting) {
        self.settings = settings
        self.defaults = defaults
        self.wrappeePresenter = wrappee
    }

    public func showConnectedNotification(serverLocation: String?, snoozeEnded: Bool) {
        if settings.notifyStatusChanges {
            wrappeePresenter.showConnectedNotification(serverLocation: serverLocation, snoozeEnded: snoozeEnded)
        }
    }

    public func showReconnectingNotification() {
        if settings.notifyStatusChanges {
            wrappeePresenter.showReconnectingNotification()
        }
    }

    public func showConnectionFailureNotification() {
        if settings.notifyStatusChanges {
            wrappeePresenter.showConnectionFailureNotification()
        }
    }

    public func showSnoozingNotification(duration: TimeInterval) {
        if settings.notifyStatusChanges {
            wrappeePresenter.showSnoozingNotification(duration: duration)
        }
    }

    public func showSupersededNotification() {
        if settings.notifyStatusChanges {
            wrappeePresenter.showSupersededNotification()
        }
    }

    public func showTestNotification() {
        if settings.notifyStatusChanges {
            wrappeePresenter.showTestNotification()
        }
    }

    public func showEntitlementNotification() {
        if defaults.showEntitlementNotification {
            defaults.showEntitlementNotification = false
            wrappeePresenter.showEntitlementNotification()
        }
    }

}
