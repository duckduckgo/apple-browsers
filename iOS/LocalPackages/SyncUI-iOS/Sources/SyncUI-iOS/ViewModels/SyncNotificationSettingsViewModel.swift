//
//  SyncNotificationSettingsViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import UserNotifications

@MainActor
public protocol SyncNotificationSettingsProviding: AnyObject {
    var isEnabled: Bool { get set }
    var isPermissionCardDismissed: Bool { get set }
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws
    func openNotificationSettings() async
}

@MainActor
public final class SyncNotificationSettingsViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus?
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isPermissionCardDismissed: Bool
    @Published private(set) var isRequestingPermission = false
    @Published var isSettingsAlertPresented = false

    private let provider: any SyncNotificationSettingsProviding

    public init(provider: any SyncNotificationSettingsProviding) {
        self.provider = provider
        isEnabled = provider.isEnabled
        isPermissionCardDismissed = provider.isPermissionCardDismissed
    }

    var isToggleOn: Bool {
        authorizationStatus == .authorized && isEnabled
    }

    var shouldShowPermissionCard: Bool {
        guard let authorizationStatus else { return false }
        return authorizationStatus != .authorized && !isPermissionCardDismissed
    }

    public func refresh() async {
        authorizationStatus = await provider.authorizationStatus()
        isEnabled = provider.isEnabled
        isPermissionCardDismissed = provider.isPermissionCardDismissed
    }

    func dismissPermissionCard() {
        provider.isPermissionCardDismissed = true
        isPermissionCardDismissed = true
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isRequestingPermission else { return }
        if !enabled {
            updateEnabledPreference(false)
            return
        }
        await enableNotifications()
    }

    func enableNotifications() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        await refresh()
        switch authorizationStatus {
        case .notDetermined, .provisional:
            do {
                // Provisional permission is quiet delivery, so it doesn't turn this toggle on.
                try await provider.requestAuthorization()
            } catch {
                await refresh()
                return
            }
            await refresh()
        case .denied:
            isSettingsAlertPresented = true
            return
        default:
            break
        }
        if authorizationStatus == .authorized {
            updateEnabledPreference(true)
        }
    }

    private func updateEnabledPreference(_ enabled: Bool) {
        provider.isEnabled = enabled
        isEnabled = enabled
    }

    func openNotificationSettings() async {
        // Retain the user's intent while they grant app-wide permission in Settings.
        updateEnabledPreference(true)
        await provider.openNotificationSettings()
    }
}
