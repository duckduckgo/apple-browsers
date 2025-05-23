//
//  DefaultBrowserAndDockPromptStatusUpdateNotifier.swift
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
import Combine

struct DefaultBrowserAndDockPromptStatusInfo: Equatable {
    let isDefaultBrowser: Bool
    let isAddedToDock: Bool
}

protocol DefaultBrowserAndDockPromptStatusNotifying {
    var statusPublisher: AnyPublisher<DefaultBrowserAndDockPromptStatusInfo, Never> { get }

    func startNotifyingStatus(interval: TimeInterval)
    func stopNotifyingStatus()
}

final class DefaultBrowserAndDockPromptStatusUpdateNotifier: DefaultBrowserAndDockPromptStatusNotifying {
    private let dockCustomizer: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let timerFactory: TimerCreating
    private var timer: TimerInterface?
    private let subject = PassthroughSubject<DefaultBrowserAndDockPromptStatusInfo, Never>()

    private var timerCancellable: Cancellable?

    var statusPublisher: AnyPublisher<DefaultBrowserAndDockPromptStatusInfo, Never> {
        subject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    init(
        dockCustomizer: DockCustomization = DockCustomizer(),
        defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider(),
        timerFactory: TimerCreating = TimerFactory()
    ) {
        self.dockCustomizer = dockCustomizer
        self.defaultBrowserProvider = defaultBrowserProvider
        self.timerFactory = timerFactory
    }

    func startNotifyingStatus(interval: TimeInterval) {
        timer = timerFactory.makeTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self, timer.isValid else { return }

            self.subject.send(.init(isDefaultBrowser: self.defaultBrowserProvider.isDefault, isAddedToDock: self.dockCustomizer.isAddedToDock))
        }
    }

    func stopNotifyingStatus() {
        timer?.invalidate()
        timer = nil
    }
}
