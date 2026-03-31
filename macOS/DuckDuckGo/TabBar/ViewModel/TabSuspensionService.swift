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

import Foundation
import PrivacyConfig

@MainActor
final class TabSuspensionService {

    private static let minimumInactiveInterval: TimeInterval = 10 * 60

    private let windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger
    private let dateProvider: () -> Date

    init(windowControllersManager: WindowControllersManagerProtocol, featureFlagger: FeatureFlagger, dateProvider: @escaping () -> Date = { Date() }) {
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger
        self.dateProvider = dateProvider

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: .memoryPressureCritical,
            object: nil
        )
    }

    @objc private func handleMemoryPressure() {
        guard featureFlagger.isFeatureOn(.tabSuspension) else { return }

        let cutoffDate = dateProvider().addingTimeInterval(-Self.minimumInactiveInterval)

        for viewModel in windowControllersManager.allTabCollectionViewModels where !viewModel.isBurner {
            let indicesToSuspend = viewModel.tabCollection.tabs.enumerated().compactMap { index, tab -> Int? in
                guard !tab.isSuspended,
                      tab.lastSelectedAt == nil || tab.lastSelectedAt! < cutoffDate
                else {
                    return nil
                }
                return index
            }

            for index in indicesToSuspend.reversed() {
                viewModel.suspendTab(at: .unpinned(index))
            }
        }
    }
}
