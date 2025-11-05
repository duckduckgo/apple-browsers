//
//  UNUserNotificationCenterRepresentable.swift
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

import UserNotifications

/// Protocol abstraction of `UNUserNotificationCenter`.
///
/// This exists to increase testability by allowing dependency injection.
/// Instead of referencing `UNUserNotificationCenter` directly, depend on this
/// protocol so that a mock or stub implementation can be provided in unit tests.
///
/// For example, production code can use the system `UNUserNotificationCenter.current()`,
/// while test code can inject a lightweight mock implementation.

protocol UNUserNotificationCenterRepresentable: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }

    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

// MARK: - UNUserNotificationCenter Extension

extension UNUserNotificationCenter: UNUserNotificationCenterRepresentable {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { cont in
            getNotificationSettings { cont.resume(returning: $0.authorizationStatus) }
        }
    }
}

// MARK: - UNAuthorizationStatus Extension

extension UNAuthorizationStatus {
    var stringValue: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .denied:        "denied"
        case .authorized:    "authorized"
        case .provisional:   "provisional"
        case .ephemeral:     "ephemeral"
        @unknown default:    "unknown"
        }
    }
}
