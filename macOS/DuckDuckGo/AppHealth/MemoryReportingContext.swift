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
    let tabs: Int
    let windows: Int
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

    /// Bucketed total tab count across all windows (0, 1, 2, 4, 7, 11, 21, 51), or `nil` if unavailable.
    let tabs: Int?

    /// Architecture of the current build ("ARM" or "Intel").
    let architecture: String

    /// Whether Sync is currently enabled (user is logged in and active), or `nil` if unavailable.
    let syncEnabled: Bool?

    /// Returns context parameters as a dictionary suitable for pixel firing.
    /// Parameters with `nil` values are sent as `"unknown"`.
    var parameters: [String: String] {
        [
            "browser_memory_mb": String(browserMemoryMB),
            "windows": windows.map(String.init) ?? "unknown",
            "tabs": tabs.map(String.init) ?? "unknown",
            "architecture": architecture,
            "sync_enabled": syncEnabled.map(String.init) ?? "unknown"
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
    @MainActor
    static func collect(
        memoryUsageMonitor: MemoryUsageMonitoring,
        windowContext: WindowContext?,
        isSyncEnabled: Bool?
    ) -> MemoryReportingContext {
        let report = memoryUsageMonitor.getCurrentMemoryUsage()
        let browserMemoryMB = MemoryReportingBuckets.bucketMemoryMB(report.physFootprintMB)
        let windows = windowContext.map(\.windows).map(MemoryReportingBuckets.bucketWindowCount)
        let tabs = windowContext.map(\.tabs).map(MemoryReportingBuckets.bucketTabCount)

        return MemoryReportingContext(
            browserMemoryMB: browserMemoryMB,
            windows: windows,
            tabs: tabs,
            architecture: MemoryReportingBuckets.currentArchitecture,
            syncEnabled: isSyncEnabled
        )
    }
}
