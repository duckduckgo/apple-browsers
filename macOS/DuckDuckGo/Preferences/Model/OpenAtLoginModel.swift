//
//  OpenAtLoginModel.swift
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

import Foundation
import os.log

@MainActor
final class OpenAtLoginModel: ObservableObject {

    @Published private(set) var status: MainAppLoginItemStatus = .notRegistered

    private let loginItem: MainAppLoginItemManaging

    init(loginItem: MainAppLoginItemManaging = MainAppLoginItem()) {
        self.loginItem = loginItem
    }

    var isSupported: Bool {
        loginItem.isSupported
    }

    /// `requiresApproval` counts as on: registration succeeded and macOS is only waiting for
    /// the user to allow the app in System Settings.
    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() async {
        status = await loginItem.status()
    }

    func setOpenAtLogin(_ enabled: Bool) async {
        status = enabled ? .enabled : .notRegistered

        do {
            if enabled {
                try await loginItem.enable()
            } else {
                try await loginItem.disable()
            }
        } catch {
            Logger.openAtLogin.error("Failed to set open at login to \(enabled, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // Re-read so a failed write reverts the checkbox instead of leaving a stale value on screen.
        await refresh()
    }

    func openSystemSettings() {
        loginItem.openSystemSettings()
    }
}
