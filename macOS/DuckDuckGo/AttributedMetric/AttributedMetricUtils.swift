//
//  AttributedMetricUtils.swift
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

import Foundation
import AttributedMetric
import BrowserServicesKit
import Subscription
import AppKit
import os.log

extension SystemDefaultBrowserProvider: AttributedMetricDefaultBrowserProviding {

    var isDefaultBrowser: Bool {
        self.isDefault
    }
}

struct DefaultAttributedMetricSettingsProvider: AttributedMetricSettingsProviding {

    let privacyConfig: PrivacyConfiguration

    var bucketsSettings: [String: Any] {
        privacyConfig.settings(for: .attributedMetrics)
    }

    var originSendList: [String] {
        guard let originSettingString = privacyConfig.settings(for: AttributedMetricsSubfeature.sendOriginParam),
              let settingsData = originSettingString.data(using: .utf8),
              let settings = try? JSONDecoder().decode(OriginSettings.self, from: settingsData) else {
            Logger.attributedMetric.error("Failed to decode origin settings, returning empty list")
            return []
        }
        return settings.originCampaignSubstrings
    }
}

struct DefaultSubscriptionStateProvider: SubscriptionStateProviding {

    let subscriptionManager: SubscriptionAuthV1toV2Bridge

    func isFreeTrial() async -> Bool {
        (try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).hasActiveTrialOffer) ?? false
    }

    var isActive: Bool {
        subscriptionManager.isUserAuthenticated
    }
}

extension AttributedMetricManager {

    func addNotificationsObserver() {

        // Register for standard notifications or specific ones coming from frameworks like Subscription and relaunch them to AttributedMetric

        // App start
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: workQueue)
            .sink { [weak self] _ in
                self?.process(trigger: .appDidStart)
            }
            .store(in: &cancellables)

        // Search

        NotificationCenter.default.publisher(for: .userDidPerformDDGSearch)
            .receive(on: workQueue)
            .sink { [weak self] _ in
                self?.process(trigger: .userDidSearch)
            }
            .store(in: &cancellables)

        // AD click

        NotificationCenter.default.publisher(for: .userDidSelectDDGAD)
            .receive(on: workQueue)
            .sink { [weak self] _ in
                self?.process(trigger: .userDidSelectAD)
            }
            .store(in: &cancellables)

        // New AI chat message sent

        NotificationCenter.default.publisher(for: .aiChatUserDidSubmitPrompt)
            .receive(on: workQueue)
            .sink { [weak self] _ in
                self?.process(trigger: .userDidDuckAIChat)
            }
            .store(in: &cancellables)

        // User purchased subscription

        NotificationCenter.default.publisher(for: .userDidPurchaseSubscription)
            .receive(on: workQueue)
            .sink { [weak self] _ in
                self?.process(trigger: .userDidSubscribe)
            }
            .store(in: &cancellables)

        // Device sync

        NotificationCenter.default.publisher(for: .syncDevicesUpdate)
            .receive(on: workQueue)
            .sink { [weak self] notification in
                guard let deviceCount = notification.userInfo?[AttributedMetricNotificationParameter.syncCount.rawValue] as? Int else {
                    assertionFailure("Missing \(AttributedMetricNotificationParameter.syncCount.rawValue)")
                    return
                }
                self?.process(trigger: .userDidSync(devicesCount: deviceCount))
            }
            .store(in: &cancellables)
    }

}
