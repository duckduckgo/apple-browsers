//
//  TabSuspensionService.swift
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
import Foundation
import PixelKit
import PrivacyConfig

enum TabSuspensionPixel: PixelKitEvent {
    case tabSuspension(trigger: String, tabsSuspended: Int, memoryReclaimedMB: Double)

    var name: String {
        switch self {
        case .tabSuspension:
            return "m_mac_tab_suspension"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .tabSuspension(let trigger, let tabsSuspended, let memoryReclaimedMB):
            return [
                "trigger": trigger,
                "tabs_suspended": String(MemoryReportingBuckets.bucketStandardTabCount(tabsSuspended)),
                "memory_reclaimed_mb": String(MemoryReportingBuckets.bucketReclaimedMemoryMB(memoryReclaimedMB))
            ]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

@MainActor
final class TabSuspensionService {

    private static let minimumInactiveInterval: TimeInterval = 10 * 60

    private let windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let pixelFiring: PixelFiring?
    private let notificationCenter: NotificationCenter
    private let dateProvider: () -> Date
    private var cancellables: Set<AnyCancellable> = []

    init(
        windowControllersManager: WindowControllersManagerProtocol,
        featureFlagger: FeatureFlagger,
        memoryUsageMonitor: MemoryUsageMonitoring,
        pixelFiring: PixelFiring?,
        notificationCenter: NotificationCenter = .default,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger
        self.memoryUsageMonitor = memoryUsageMonitor
        self.pixelFiring = pixelFiring
        self.notificationCenter = notificationCenter
        self.dateProvider = dateProvider

        notificationCenter.publisher(for: .memoryPressureCritical)
            .sink { [weak self] notification in
                self?.handleMemoryPressure(notification)
            }
            .store(in: &cancellables)
    }

    private func handleMemoryPressure(_ notification: Notification) {
        guard featureFlagger.isFeatureOn(.tabSuspension) else { return }

        let initialMemoryBytes: UInt64
        if let context = notification.userInfo?[MemoryPressureNotification.contextKey] as? MemoryReportingContext {
            initialMemoryBytes = context.totalMemoryBytes
        } else {
            let report = memoryUsageMonitor.getCurrentMemoryUsage()
            initialMemoryBytes = report.physFootprintBytes + (report.webContentBytes ?? 0)
        }

        let cutoffDate = dateProvider().addingTimeInterval(-Self.minimumInactiveInterval)
        var suspendedCount = 0

        for viewModel in windowControllersManager.allTabCollectionViewModels where !viewModel.isBurner {
            for (index, tab) in viewModel.tabCollection.tabs.enumerated() where !tab.isSuspended {
                if tab.lastSelectedAt == nil || tab.lastSelectedAt! < cutoffDate {
                    if viewModel.suspendTab(at: .unpinned(index)) {
                        suspendedCount += 1
                    }
                }
            }
        }

        guard suspendedCount > 0 else { return }

        let postReport = memoryUsageMonitor.getCurrentMemoryUsage()
        let postMemoryBytes = postReport.physFootprintBytes + (postReport.webContentBytes ?? 0)
        let reclaimedBytes = initialMemoryBytes > postMemoryBytes ? initialMemoryBytes - postMemoryBytes : 0
        let reclaimedMB = Double(reclaimedBytes) / 1_048_576.0

        pixelFiring?.fire(
            TabSuspensionPixel.tabSuspension(
                trigger: "critical_memory_pressure",
                tabsSuspended: suspendedCount,
                memoryReclaimedMB: reclaimedMB
            ),
            frequency: .standard
        )
    }
}
