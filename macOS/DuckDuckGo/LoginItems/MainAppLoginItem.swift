//
//  MainAppLoginItem.swift
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

import AppKit
import Foundation
import ServiceManagement

enum MainAppLoginItemStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    @available(macOS 13.0, *)
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

/// Registers the browser itself to launch when the user logs in to macOS.
/// Distinct from `LoginItemsManager`, which manages the VPN and DBP helper agents.
protocol MainAppLoginItemManaging {
    /// False below macOS 13, where `SMAppService.mainApp` is unavailable.
    var isSupported: Bool { get }

    func status() async -> MainAppLoginItemStatus
    func enable() async throws
    func disable() async throws

    @MainActor
    func openSystemSettings()
}

struct MainAppLoginItem: MainAppLoginItemManaging {

    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    /// `SMAppService` reads perform synchronous XPC to the Service Management daemon, so they are
    /// dispatched onto a detached `Task` to keep them off the caller's thread.
    func status() async -> MainAppLoginItemStatus {
        guard #available(macOS 13.0, *) else { return .notFound }

        return await Task.detached {
            MainAppLoginItemStatus(SMAppService.mainApp.status)
        }.value
    }

    func enable() async throws {
        guard #available(macOS 13.0, *) else { return }

        try await Task.detached {
            try SMAppService.mainApp.register()
        }.value
    }

    func disable() async throws {
        guard #available(macOS 13.0, *) else { return }

        try await Task.detached {
            try SMAppService.mainApp.unregister()
        }.value
    }

    @MainActor
    func openSystemSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            let loginItemsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
            NSWorkspace.shared.open(loginItemsURL)
        }
    }
}
