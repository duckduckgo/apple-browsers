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

@MainActor
final class TabSuspensionService {

    private static let minimumInactiveInterval: TimeInterval = 10 * 60

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryPressure),
            name: .memoryPressureCritical,
            object: nil
        )
    }

    @objc private func handleMemoryPressure() {
        let cutoffDate = Date().addingTimeInterval(-Self.minimumInactiveInterval)

        for viewModel in windowControllersManager.allTabCollectionViewModels {
            let tabs = viewModel.tabCollection.tabs
            for (index, tab) in tabs.enumerated() {
                guard !tab.isSuspended else { continue }
                guard let lastSelectedAt = tab.lastSelectedAt, lastSelectedAt < cutoffDate else { continue }

                viewModel.suspendTab(at: .unpinned(index))
            }
        }
    }
}
