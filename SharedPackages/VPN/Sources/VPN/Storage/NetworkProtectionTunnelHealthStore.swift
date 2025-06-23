//
//  NetworkProtectionTunnelHealthStore.swift
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
import Common
import os.log

/// Stores information about NetP's tunnel health
///
public final class NetworkProtectionTunnelHealthStore {
    private static let isHavingConnectivityIssuesKey = "com.duckduckgo.isHavingConnectivityIssues"
    private let userDefaults: UserDefaults

#if os(macOS)

    private let notificationCenter: NetworkProtectionNotificationCenter

    public init(userDefaults: UserDefaults = .standard,
                notificationCenter: NetworkProtectionNotificationCenter) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    // MARK: - Posting Issue Notifications

    private func postIssueChangeNotification(newValue: Bool) {
        if newValue {
            notificationCenter.post(.issuesStarted)
        } else {
            notificationCenter.post(.issuesResolved)
        }
    }

#else

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

#endif

    var isHavingConnectivityIssues: Bool {
        get {
            userDefaults.bool(forKey: Self.isHavingConnectivityIssuesKey)
        }

        set {
            guard newValue != userDefaults.bool(forKey: Self.isHavingConnectivityIssuesKey) else {
                return
            }
            userDefaults.set(newValue, forKey: Self.isHavingConnectivityIssuesKey)
            Logger.networkProtectionConnectionTester.log("Issues set to \(String(reflecting: newValue), privacy: .public)")
#if os(macOS)
            postIssueChangeNotification(newValue: newValue)
#endif
        }
    }
}
