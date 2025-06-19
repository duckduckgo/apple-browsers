//
//  UserDefaults+showMessaging.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import Common

extension UserDefaults {
    private var showEntitlementAlertKey: String {
        "showEntitlementAlert"
    }

    @objc
    public dynamic var showEntitlementAlert: Bool {
        get {
            value(forKey: showEntitlementAlertKey) as? Bool ?? false
        }

        set {
            if newValue == true {
                /// Only show alert if it hasn't been shown before
                if value(forKey: showEntitlementAlertKey) == nil {
                    set(newValue, forKey: showEntitlementAlertKey)
                }
            } else {
                set(newValue, forKey: showEntitlementAlertKey)
            }
        }
    }

    private var showEntitlementNotificationKey: String {
        "showEntitlementNotification"
    }

    @objc
    public dynamic var showEntitlementNotification: Bool {
        get {
            value(forKey: showEntitlementNotificationKey) as? Bool ?? false
        }

        set {
            if newValue == true {
                /// Only show notification if it hasn't been shown before
                if value(forKey: showEntitlementNotificationKey) == nil {
                    set(newValue, forKey: showEntitlementNotificationKey)
                }
            } else {
                set(newValue, forKey: showEntitlementNotificationKey)
            }
        }
    }

    public func enableEntitlementMessaging() {
        showEntitlementAlert = true
        showEntitlementNotification = true

#if os(iOS)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(rawValue: Notification.Name.vpnEntitlementMessagingDidChange.rawValue as CFString),
                                             nil, nil, true)
#endif
    }

    public func resetEntitlementMessaging() {
        removeObject(forKey: showEntitlementAlertKey)
        removeObject(forKey: showEntitlementNotificationKey)
    }
}

public extension Notification.Name {
    static let vpnEntitlementMessagingDidChange = Notification.Name("com.duckduckgo.network-protection.entitlement-messaging-changed")
}
