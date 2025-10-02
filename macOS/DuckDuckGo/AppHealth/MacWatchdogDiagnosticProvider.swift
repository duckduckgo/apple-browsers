//
//  MacWatchdogDiagnosticProvider.swift
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
import BrowserServicesKit
import IOKit.ps

/// Concrete WatchdogDiagnosticProvider implementation for macOS
///
public class MacWatchdogDiagnosticProvider: WatchdogDiagnosticProvider {

    /// WindowControllersManager is used to determine number of open windows and tabs.
    private let windowControllersManager: WindowControllersManagerProtocol?

    init(windowControllersManager: WindowControllersManagerProtocol? = nil) {
        self.windowControllersManager = windowControllersManager
    }

    public func collectDiagnostics(for event: Watchdog.Event) async -> WatchdogDiagnostics {
        // We can only collect diagnostics that require access to the main thread for recovered hangs, as the main thread will otherwise be blocked.
        switch event {
        case .uiHangRecovered:
            return await collectDiagnosticsForRecoveredHang()
        default:
            return collectDiagnosticsForNotRecoveredHang()
        }
    }

    private func collectDiagnosticsForRecoveredHang() async -> WatchdogDiagnostics {
        let isInForeground = await isInForeground()
        let isAnyWindowVisible = await isAnyWindowVisible()
        let openBrowserWindowCount = await openBrowserWindowCount()
        let openBrowserTabCount = await openBrowserTabCount()

        return WatchdogDiagnostics(isInForeground: isInForeground, isAnyWindowVisible: isAnyWindowVisible, isOnBattery: isOnBattery, openBrowserWindowCount: openBrowserWindowCount, openBrowserTabCount: openBrowserTabCount)
    }

    private func collectDiagnosticsForNotRecoveredHang() -> WatchdogDiagnostics {
        return WatchdogDiagnostics(isInForeground: nil, isAnyWindowVisible: nil, isOnBattery: isOnBattery, openBrowserWindowCount: nil, openBrowserTabCount: nil)
    }

    // MARK: - Helper methods

    private func isInForeground() async -> Bool? {
        return await MainActor.run {
            NSApplication.shared.isActive
        }
    }

    private func isAnyWindowVisible() async -> Bool? {
        return await MainActor.run {
            NSApplication.shared.windows.contains { $0.isVisible }
        }
    }

    private var isOnBattery: Bool? {
        let powerSource = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let powerSourcesList = IOPSCopyPowerSourcesList(powerSource)?.takeRetainedValue() as? [CFTypeRef]

        guard let sources = powerSourcesList, !sources.isEmpty else { return nil }

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(powerSource, source)?.takeUnretainedValue() as? [String: Any],
               let powerSourceState = description[kIOPSPowerSourceStateKey] as? String {
                return powerSourceState == kIOPSBatteryPowerValue
            }
        }

        return nil
    }

    private func openBrowserWindowCount() async -> Int? {
        return await MainActor.run {
            windowControllersManager?.mainWindowControllers.count
        }
    }

    private func openBrowserTabCount() async -> Int? {
        return await MainActor.run {
            windowControllersManager?.allTabCollectionViewModels
                .reduce(0) { $0 + $1.allTabsCount }
        }
    }
}
