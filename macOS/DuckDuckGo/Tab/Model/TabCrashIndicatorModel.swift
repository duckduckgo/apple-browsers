//
//  TabCrashIndicatorModel.swift
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

import Combine
import Foundation

/// This class manages the visibility of tab crash indicator.
///
final class TabCrashIndicatorModel: ObservableObject {
    @Published private(set) var recentTabCrash: TabCrashType?
    @Published var isShowingPopover: Bool = false

    func setUp(with tab: Tab) {
        /// Crash events from Tab instance
        let crashPublisher = tab.crashPublisher.map(TabCrashType?.some).share()

        /// Resetting recent crash after timeout (responsible for clearing the crash icon)
        let resetRecentTabCrashAfterTimeout = crashPublisher
            .debounce(for: Const.maxIndicatorPresentationDuration, scheduler: RunLoop.main)
            .filter { [weak self] tabCrashType in
                return self?.isShowingPopover == false
            }
            .map { _ in TabCrashType?.none }

        /// Resetting recent crash after dismissing popover
        let resetRecentTabCrashOnPopoverDismiss = $isShowingPopover.dropFirst()
            .filter { !$0 }
            .map { _ in TabCrashType?.none }

        Publishers.Merge3(crashPublisher, resetRecentTabCrashAfterTimeout, resetRecentTabCrashOnPopoverDismiss)
            .removeDuplicates()
            .assign(to: \.recentTabCrash, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    enum Const {
        static let maxIndicatorPresentationDuration: RunLoop.SchedulerTimeType.Stride = .seconds(20)
        static let popoverWidth: CGFloat = 252
    }

    private var cancellables: Set<AnyCancellable> = []
}
