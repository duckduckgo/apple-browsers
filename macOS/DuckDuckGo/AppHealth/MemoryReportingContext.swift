//
//  MemoryReportingContext.swift
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

/// A snapshot of current windows and tabs in use
struct WindowContext {
    let standardTabs: Int
    let pinnedTabs: Int
    let windows: Int
}

extension WindowContext {

    @MainActor
    init(windowControllersManager: WindowControllersManager) {
        standardTabs = windowControllersManager.allTabCollectionViewModels.reduce(0) { $0 + $1.tabCollection.tabs.count }
        pinnedTabs = windowControllersManager.pinnedTabsManagerProvider.currentPinnedTabManagers.reduce(0) { $0 + $1.tabCollection.tabs.count }
        windows = windowControllersManager.mainWindowControllers.count
    }
}

/// A snapshot of context collected at the moment of firing a memory usage pixel.
///
/// All values are pre-bucketed using `MemoryReportingBuckets` to match the pixel parameter
/// definitions. Context is collected from the memory monitor, window controllers manager,
/// and sync service.
///
struct MemoryReportingContext {

    /// Bucketed browser memory usage in MB (0, 512, 1024, 2048, 4096, 8192, 16384).
    let browserMemoryMB: Int

    /// Bucketed number of open windows (0, 1, 2, 4, 7, 11, 21), or `nil` if unavailable.
    let windows: Int?

    /// Bucketed standard (unpinned) tab count across all windows (0, 1, 2, 4, 7, 11, 21, 51), or `nil` if unavailable.
    let standardTabs: Int?

    /// Bucketed pinned tab count across all windows (0, 1, 2, 4, 7, 11, 15), or `nil` if unavailable.
    let pinnedTabs: Int?

    /// Architecture of the current build ("ARM" or "Intel").
    let architecture: String

    /// Whether Sync is currently enabled (user is logged in and active), or `nil` if unavailable.
    let syncEnabled: Bool?

    /// Bucketed total used allocation in MB (0, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384), or `nil` if unavailable.
    let usedAllocationMB: Int?

    /// Bucketed total WebContent process memory in MB (0, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536),
    /// or `nil` if WebContent process memory could not be measured.
    let wcTotalMemoryMB: Int?

    /// Minutes elapsed since app launch (raw value, not bucketed).
    let uptimeMinutes: Int

    /// Returns context parameters as a dictionary suitable for pixel firing.
    /// Parameters with `nil` values are sent as `"unknown"`.
    var parameters: [String: String] {
        [
            "browser_memory_mb": String(browserMemoryMB),
            "windows": windows.map(String.init) ?? "unknown",
            "standard_tabs": standardTabs.map(String.init) ?? "unknown",
            "pinned_tabs": pinnedTabs.map(String.init) ?? "unknown",
            "architecture": architecture,
            "sync_enabled": syncEnabled.map(String.init) ?? "unknown",
            "used_allocation": usedAllocationMB.map(String.init) ?? "unknown",
            "wc_total_memory": wcTotalMemoryMB.map(String.init) ?? "unknown",
            "uptime": String(uptimeMinutes)
        ]
    }

    /// Collects and buckets current context from the provided sources.
    ///
    /// - Parameters:
    ///   - memoryUsageMonitor: Provides current memory usage via `getCurrentMemoryUsage()`
    ///   - windowContext: Snapshot of current window and tab counts. Pass `nil` if unavailable;
    ///     window and tab counts will be sent as `"unknown"`.
    ///   - isSyncEnabled: Whether sync is currently enabled. Pass `nil` if unavailable;
    ///     sync status will be sent as `"unknown"`.
    ///   - usedAllocationBytes: Total used bytes from malloc zones. Pass `nil` if unavailable.
    ///   - launchDate: The date the app was launched, used to compute uptime in minutes.
    @MainActor
    static func collect(
        memoryUsageMonitor: MemoryUsageMonitoring,
        windowContext: WindowContext?,
        isSyncEnabled: Bool?,
        usedAllocationBytes: UInt64?,
        launchDate: Date
    ) -> MemoryReportingContext {
        let report = memoryUsageMonitor.getCurrentMemoryUsage()
        let browserMemoryMB = MemoryReportingBuckets.bucketMemoryMB(report.physFootprintMB)
        let windows = windowContext.map(\.windows).map(MemoryReportingBuckets.bucketWindowCount)
        let standardTabs = windowContext.map(\.standardTabs).map(MemoryReportingBuckets.bucketStandardTabCount)
        let pinnedTabs = windowContext.map(\.pinnedTabs).map(MemoryReportingBuckets.bucketPinnedTabCount)
        let usedAllocationMB = usedAllocationBytes.map { bytes in
            MemoryReportingBuckets.bucketUsedAllocationMB(Double(bytes) / 1_048_576.0)
        }
        let wcTotalMemoryMB = report.webContentMB.map(MemoryReportingBuckets.bucketWebContentMemoryMB)
        let uptimeMinutes = Int(Date().timeIntervalSince(launchDate) / 60.0)

        return MemoryReportingContext(
            browserMemoryMB: browserMemoryMB,
            windows: windows,
            standardTabs: standardTabs,
            pinnedTabs: pinnedTabs,
            architecture: MemoryReportingBuckets.currentArchitecture,
            syncEnabled: isSyncEnabled,
            usedAllocationMB: usedAllocationMB,
            wcTotalMemoryMB: wcTotalMemoryMB,
            uptimeMinutes: uptimeMinutes
        )
    }
}
