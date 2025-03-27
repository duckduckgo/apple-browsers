//
//  KnownFailureObserverThroughDistributedNotifications.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public class KnownFailureObserverThroughDistributedNotifications: KnownFailureObserver {
    public lazy var publisher = subject.eraseToAnyPublisher()
    public var recentValue: KnownFailure? {
        subject.value
    }

    private let subject = CurrentValueSubject<KnownFailure?, Never>(nil)

    private let distributedNotificationCenter: DistributedNotificationCenter
    private var cancellable: AnyCancellable?

    public init(distributedNotificationCenter: DistributedNotificationCenter = .default()) {
        self.distributedNotificationCenter = distributedNotificationCenter

        start()
    }

    private func start() {
        cancellable = distributedNotificationCenter.publisher(for: .knownFailureUpdated).sink { [weak self] notification in
            self?.handleKnownFailureUpdated(notification)
        }
    }

    private func handleKnownFailureUpdated(_ notification: Notification) {
        if let object = notification.object as? String,
           let data = object.data(using: .utf8),
           let failure = try? JSONDecoder().decode(KnownFailure.self, from: data) {
            subject.send(failure)
        } else {
            subject.send(nil)
        }
    }
}

#endif
