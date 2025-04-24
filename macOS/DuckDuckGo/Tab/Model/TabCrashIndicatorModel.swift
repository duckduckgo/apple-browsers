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
/// Tab crash indicator is a small info icon displayed in the tab bar item
/// for a crashed tab. When clicked, it displays a popover explaining that
/// the tab crashed and was reloaded which may have caused data loss.
///
final class TabCrashIndicatorModel: ObservableObject {

    @Published private(set) var isShowingIndicator: Bool = false
    @Published var isShowingPopover: Bool = false

    /// This initializer allows for parametrizing presentation duration
    /// in order to simplify unit testing.
    init(maxPresentationDuration: RunLoop.SchedulerTimeType.Stride = Const.maxIndicatorPresentationDuration) {
        self.maxPresentationDuration = maxPresentationDuration
    }

    func setUp(with crashPublisher: AnyPublisher<TabCrashType, Never>) {
        /// We're only showing the icon on "single" crashes (and we're hiding it on crash loops).
        let showIndicatorOnSingleCrash = crashPublisher
            .map { $0 == .single }
            .share()

        /// We're auto-hiding the icon after a predefined time, but only if the popover isn't on screen.
        /// If the popover is displayed, we're not auto-hiding and instead we'll hide the icon as soon
        /// as the popover is dismissed.
        let hideIndicatorAfterTimeout = showIndicatorOnSingleCrash
            .debounce(for: maxPresentationDuration, scheduler: RunLoop.main)
            .filter { [weak self] _ in
                self?.isShowingPopover == false
            }
            .map { _ in false }

        /// Hiding the icon after dismissing the popover.
        let hideIndicatorOnPopoverDismiss = $isShowingPopover.dropFirst()
            .filter { !$0 }
            .map { _ in false }

        Publishers.Merge3(showIndicatorOnSingleCrash, hideIndicatorAfterTimeout, hideIndicatorOnPopoverDismiss)
            .removeDuplicates()
            .assign(to: \.isShowingIndicator, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    enum Const {
        static let maxIndicatorPresentationDuration: RunLoop.SchedulerTimeType.Stride = .seconds(20)
        static let popoverWidth: CGFloat = 252
    }

    private let maxPresentationDuration: RunLoop.SchedulerTimeType.Stride
    private var cancellables: Set<AnyCancellable> = []
}
