//
//  ConnectivityIssueObserverThroughDistributedNotifications.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

#if os(macOS)

import Combine
import Foundation
import NetworkExtension
import NotificationCenter
import Common
import os.log

/// Observes the tunnel status through Distributed Notifications.
///
public class ConnectivityIssueObserverThroughDistributedNotifications: ConnectivityIssueObserver {
    public lazy var publisher: AnyPublisher<Bool, Never> = subject.eraseToAnyPublisher()
    public var recentValue: Bool {
        subject.value
    }

    private let subject = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Notifications

    private let distributedNotificationCenter: DistributedNotificationCenter
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(distributedNotificationCenter: DistributedNotificationCenter = .default()) {

        self.distributedNotificationCenter = distributedNotificationCenter
        start()
    }

    private func start() {
        distributedNotificationCenter.publisher(for: .issuesStarted).sink { [weak self] _ in
            guard let self else { return }

            logIssuesChanged(isHavingIssues: true)
            subject.send(true)
        }.store(in: &cancellables)

        distributedNotificationCenter.publisher(for: .issuesResolved).sink { [weak self] _ in
            guard let self else { return }

            logIssuesChanged(isHavingIssues: false)
            subject.send(false)
        }.store(in: &cancellables)
    }

    private func logIssuesChanged(isHavingIssues: Bool) {
        if isHavingIssues {
            Logger.networkProtectionStatusReporter.debug("\(String(describing: self), privacy: .public): issues started")
        } else {
            Logger.networkProtectionStatusReporter.debug("\(String(describing: self), privacy: .public): issues stopped")
        }
    }
}

#endif
