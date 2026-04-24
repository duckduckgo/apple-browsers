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
import Common
import Foundation
import os.log
import Persistence
import PixelKit
import PrivacyConfig

enum TabSuspensionPixel: PixelKitEvent {

    enum Trigger: String {
        case criticalMemoryPressure = "critical_memory_pressure"
    }

    case tabSuspension(trigger: Trigger, tabsSuspended: Int, memoryReclaimedMB: Double)

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
                "trigger": trigger.rawValue,
                "tabs_suspended": String(MemoryReportingBuckets.bucketStandardTabCount(tabsSuspended)),
                "memory_reclaimed_mb": String(MemoryReportingBuckets.bucketReclaimedMemoryMB(memoryReclaimedMB))
            ]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

@MainActor
final class TabSuspensionService {

    private static let defaultMinimumInactiveInterval: TimeInterval = 10 * 60
    private static let debugMinimumInactiveInterval: TimeInterval = 5

    enum Key: String {
        case useShortInactiveInterval = "debug.tab-suspension.use-short-inactive-interval"
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let memoryProvider: (pid_t) -> UInt64?
    private let pixelFiring: PixelFiring?
    private let notificationCenter: NotificationCenter
    private let dateProvider: () -> Date
    private var cancellables: Set<AnyCancellable> = []

    var useShortInactiveInterval: Bool {
        get {
            // always use short interval in UI tests
            if AppVersion.runType == .uiTests {
                return true
            }
            let storedValue = (try? keyValueStore.object(forKey: Key.useShortInactiveInterval.rawValue) as? Bool) ?? false
            // only allow to override interval for internal users
            return featureFlagger.internalUserDecider.isInternalUser ? storedValue : false
        }

        set {
            try? keyValueStore.set(newValue, forKey: Key.useShortInactiveInterval.rawValue)
        }
    }

    private var minimumInactiveInterval: TimeInterval {
        if useShortInactiveInterval {
            return Self.debugMinimumInactiveInterval
        }
        if let settingsJSON = privacyConfigurationManager.privacyConfig.settings(for: TabSuspensionSubfeature.memoryPressureTrigger),
           let jsonData = settingsJSON.data(using: .utf8),
           let settings = try? JSONDecoder().decode(MemoryPressureTriggerSettings.self, from: jsonData) {
            return settings.tabInactivityPeriod
        }
        return Self.defaultMinimumInactiveInterval
    }

    init(
        windowControllersManager: WindowControllersManagerProtocol,
        featureFlagger: FeatureFlagger,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        pixelFiring: PixelFiring?,
        keyValueStore: ThrowingKeyValueStoring,
        memoryProvider: @escaping (pid_t) -> UInt64?,
        notificationCenter: NotificationCenter = .default,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.pixelFiring = pixelFiring
        self.keyValueStore = keyValueStore
        self.memoryProvider = memoryProvider
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

        Logger.tabSuspension.info("Critical memory pressure event received, starting tab suspension")

        let cutoffDate = dateProvider().addingTimeInterval(-minimumInactiveInterval)
        var suspendedCount = 0
        var reclaimedBytes: UInt64 = 0

        for viewModel in windowControllersManager.allTabCollectionViewModels where !viewModel.isBurner {
            for (index, tab) in viewModel.tabCollection.tabs.enumerated() where !tab.isSuspended {
                if tab.lastSelectedAt == nil || tab.lastSelectedAt! < cutoffDate {
                    let webProcessMemory: UInt64 = {
                        guard case let .loaded(loadedTab) = tab,
                              let pid = loadedTab.webView.webProcessIdentifier,
                              let memory = memoryProvider(pid)
                        else {
                            return 0
                        }
                        return memory
                    }()
                    if viewModel.suspendTab(at: .unpinned(index)) {
                        suspendedCount += 1
                        reclaimedBytes += webProcessMemory
                    }
                }
            }
        }

        guard suspendedCount > 0 else {
            Logger.tabSuspension.info("No tabs were eligible for suspension")
            return
        }

        let pixelFiring = self.pixelFiring

        let reclaimedMB = Double(reclaimedBytes) / 1_048_576.0

        Logger.tabSuspension.info("Suspended \(suspendedCount) tab(s), memory reclaimed: \(String(format: "%.1f", reclaimedMB)) MB")

        pixelFiring?.fire(
            TabSuspensionPixel.tabSuspension(
                trigger: .criticalMemoryPressure,
                tabsSuspended: suspendedCount,
                memoryReclaimedMB: reclaimedMB
            ),
            frequency: .dailyAndCount
        )
    }
}

private struct MemoryPressureTriggerSettings: Decodable {
    let tabInactivityPeriod: TimeInterval
}
