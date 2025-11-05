//
//  MockUNUserNotificationCenter.swift
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

@testable import DuckDuckGo
import UserNotifications

enum MockPushNotificationError: Error {
    case addRequestError
    case requestAuthError
}

final class MockUNUserNotificationCenter: UNUserNotificationCenterRepresentable {
    var delegate: UNUserNotificationCenterDelegate?
    
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var addRequestError: MockPushNotificationError?
    var requestAuthError: MockPushNotificationError?
    
    // Spies
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []
    private(set) var didCheckAuthorizationStatus = false
    private(set) var didRequestAuthorization = false
    private(set) var requestedAuthorizationOptions: UNAuthorizationOptions = []
    
    func authorizationStatus() async -> UNAuthorizationStatus {
        didCheckAuthorizationStatus = true
        return authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        didRequestAuthorization = true
        requestedAuthorizationOptions = options
        if let requestAuthError { throw requestAuthError }
        if options.contains(.provisional) {
            authorizationStatus = .provisional
        }
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let addRequestError { throw addRequestError }
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        let set = Set(identifiers)
        addedRequests.removeAll { set.contains($0.identifier) }
    }
}
