//
//  DataVolumeObserverThroughSession.swift
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

import Combine
import Foundation
import NetworkExtension
import NotificationCenter
import Common
import os.log

public class DataVolumeObserverThroughSession: DataVolumeObserver {
    public lazy var publisher = subject.eraseToAnyPublisher()
    public var recentValue: DataVolume {
        subject.value
    }

    private let subject = CurrentValueSubject<DataVolume, Never>(.init())

    private let tunnelSessionProvider: TunnelSessionProvider

    // MARK: - Notifications

    private let platformNotificationCenter: NotificationCenter
    private let platformDidWakeNotification: Notification.Name
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Timer

    private static let interval: TimeInterval = .seconds(1)

    // MARK: - Initialization

    public init(tunnelSessionProvider: TunnelSessionProvider,
                platformNotificationCenter: NotificationCenter,
                platformDidWakeNotification: Notification.Name) {

        self.platformNotificationCenter = platformNotificationCenter
        self.platformDidWakeNotification = platformDidWakeNotification
        self.tunnelSessionProvider = tunnelSessionProvider

        start()
    }

    public func start() {
        updateDataVolume()

        Timer.publish(every: Self.interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDataVolume()
            }.store(in: &cancellables)

        platformNotificationCenter.publisher(for: platformDidWakeNotification).sink { [weak self] notification in
            self?.handleDidWake(notification)
        }.store(in: &cancellables)
    }

    // MARK: - Handling Notifications

    private func handleDidWake(_ notification: Notification) {
        updateDataVolume()
    }

    // MARK: - Obtaining the data volume

    private func updateDataVolume(session: NETunnelProviderSession) async {
        guard let data: ExtensionMessageString = try? await session.sendProviderMessage(.getDataVolume) else {
            return
        }

        let bytes = data.value.components(separatedBy: ",")
        guard let receivedString = bytes.first, let sentString = bytes.last,
              let received = Int64(receivedString), let sent = Int64(sentString) else {
            return
        }

        subject.send(DataVolume(bytesSent: sent, bytesReceived: received))
    }

    private func updateDataVolume() {
        Task {
            guard let session = await tunnelSessionProvider.activeSession(),
                session.status == .connected else {

                return
            }

            await updateDataVolume(session: session)
        }
    }
}
