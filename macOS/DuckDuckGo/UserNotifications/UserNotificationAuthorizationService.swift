//
//  UserNotificationAuthorizationService.swift
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

import AppKit
import Foundation
import Combine
import UserNotifications

protocol UserNotificationAuthorizationServicing: AnyObject {
    /// Returns the current authorization status (async because it requires fetching from UNUserNotificationCenter)
    var authorizationStatus: UNAuthorizationStatus { get async }

    /// Returns the cached authorization status (sync, may be briefly stale at app launch)
    var cachedAuthorizationStatus: UNAuthorizationStatus { get }

    /// Publisher that emits when authorization status changes
    /// Initial value will be .notDetermined, then updated after first async fetch
    var authorizationStatusPublisher: AnyPublisher<UNAuthorizationStatus, Never> { get }

    /// Request notification authorization from the system
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

final class UserNotificationAuthorizationService: UserNotificationAuthorizationServicing {
    @PublishedAfter private var currentAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter: WebNotificationService
    private var appActivationCancellable: AnyCancellable?
    /// macOS can keep reporting `.notDetermined` after notifications are turned off in System Settings, while it
    /// refuses every request without asking. Such a refusal is reported as `.denied` until macOS reports a decision.
    private var isRequestRefusedBySystem = false

    var authorizationStatus: UNAuthorizationStatus {
        get async {
            let status = await notificationCenter.authorizationStatus()
            guard status == .notDetermined else {
                isRequestRefusedBySystem = false
                return status
            }
            return isRequestRefusedBySystem ? .denied : status
        }
    }

    var cachedAuthorizationStatus: UNAuthorizationStatus {
        currentAuthorizationStatus
    }

    var authorizationStatusPublisher: AnyPublisher<UNAuthorizationStatus, Never> {
        $currentAuthorizationStatus.eraseToAnyPublisher()
    }

    init(
        notificationCenter: WebNotificationService = UNUserNotificationCenter.current(),
        appActivationPublisher: AnyPublisher<Notification, Never> = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .eraseToAnyPublisher()
    ) {
        self.notificationCenter = notificationCenter

        Task {
            await updateAuthorizationStatus()
        }

        self.appActivationCancellable = appActivationPublisher
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.updateAuthorizationStatus()
                }
            }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: options)
            await updateAuthorizationStatus()
            return granted
        } catch {
            if (error as? UNError)?.code == .notificationsNotAllowed {
                isRequestRefusedBySystem = true
            }
            await updateAuthorizationStatus()
            throw error
        }
    }

    private func updateAuthorizationStatus() async {
        let newStatus = await authorizationStatus
        if newStatus != currentAuthorizationStatus {
            currentAuthorizationStatus = newStatus
        }
    }
}
