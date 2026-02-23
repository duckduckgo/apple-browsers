//
//  AutoconsentEventCoordinator.swift
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
import Combine
import AutoconsentStats
import History
import PrivacyConfig
import WebExtensions

/// Coordinates autoconsent events from both user scripts and web extensions,
/// ensuring stats are recorded once and history is updated centrally.
final class AutoconsentEventCoordinator {

    private var cancellables = Set<AnyCancellable>()
    private let autoconsentStats: AutoconsentStatsCollecting
    private let historyCoordinating: HistoryCoordinating
    private let featureFlagger: FeatureFlagger
    private let webExtensionAvailability: WebExtensionAvailabilityProviding

    init(autoconsentStats: AutoconsentStatsCollecting,
         historyCoordinating: HistoryCoordinating,
         featureFlagger: FeatureFlagger,
         webExtensionAvailability: WebExtensionAvailabilityProviding) {

        self.autoconsentStats = autoconsentStats
        self.historyCoordinating = historyCoordinating
        self.featureFlagger = featureFlagger
        self.webExtensionAvailability = webExtensionAvailability

        subscribeToNotifications()
    }

    private func subscribeToNotifications() {
        subscribeToUserScriptNotifications()
        subscribeToWebExtensionNotifications()
    }

    private func subscribeToUserScriptNotifications() {
        NotificationCenter.default
            .publisher(for: AutoconsentPopupManagedEvent.userScriptPopupManagedNotification)
            .compactMap { [weak self] notification -> AutoconsentPopupManagedEvent? in
                guard self?.webExtensionAvailability.isAutoconsentExtensionAvailable == false,
                      let userInfo = notification.userInfo else {
                    return nil
                }
                return AutoconsentPopupManagedEvent(from: userInfo, source: .userScript)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.processEvent(event)
            }
            .store(in: &cancellables)
    }

    private func subscribeToWebExtensionNotifications() {
        NotificationCenter.default
            .publisher(for: AutoconsentPopupManagedEvent.webExtensionPopupManagedNotification)
            .compactMap { [weak self] notification -> AutoconsentPopupManagedEvent? in
                guard self?.webExtensionAvailability.isAutoconsentExtensionAvailable == true,
                      let userInfo = notification.userInfo else {
                    return nil
                }
                return AutoconsentPopupManagedEvent(from: userInfo, source: .webExtension)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.processEvent(event)
            }
            .store(in: &cancellables)
    }

    private func processEvent(_ event: AutoconsentPopupManagedEvent) {
        recordStats(from: event)
        updateHistory(from: event)
    }

    private func recordStats(from event: AutoconsentPopupManagedEvent) {
        Task {
            guard featureFlagger.isFeatureOn(.newTabPageAutoconsentStats) else { return }

            let durationInSeconds: TimeInterval = event.duration / 1000.0
            await autoconsentStats.recordAutoconsentAction(
                clicksMade: Int64(event.totalClicks),
                timeSpent: durationInSeconds
            )
        }
    }

    private func updateHistory(from event: AutoconsentPopupManagedEvent) {
        Task { @MainActor in
            self.historyCoordinating.cookiePopupBlocked(on: event.url)
        }
    }
}
