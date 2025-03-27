//
//  MockNetworkProtectionStatusReporter.swift
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
import NetworkExtension
import Common
import NetworkProtection

/// This is the default status reporter.
///
public final class MockNetworkProtectionStatusReporter: NetworkProtectionStatusReporter {

    // MARK: - Publishers

    public let statusObserver: ConnectionStatusObserver
    public let serverInfoObserver: ConnectionServerInfoObserver
    public let connectionErrorObserver: ConnectionErrorObserver
    public let connectivityIssuesObserver: ConnectivityIssueObserver
    public let controllerErrorMessageObserver: ControllerErrorMesssageObserver
    public let dataVolumeObserver: DataVolumeObserver
    public let knownFailureObserver: KnownFailureObserver

    // MARK: - Init & deinit

    public init(statusObserver: ConnectionStatusObserver = MockConnectionStatusObserver(),
                serverInfoObserver: ConnectionServerInfoObserver = MockConnectionServerInfoObserver(),
                connectionErrorObserver: ConnectionErrorObserver = MockConnectionErrorObserver(),
                connectivityIssuesObserver: ConnectivityIssueObserver = MockConnectivityIssueObserver(),
                controllerErrorMessageObserver: ControllerErrorMesssageObserver = MockControllerErrorMesssageObserver(),
                dataVolumeObserver: DataVolumeObserver = MockDataVolumeObserver(),
                knownFailureObserver: KnownFailureObserver = MockKnownFailureObserver(),
                distributedNotificationCenter: DistributedNotificationCenter = .default()) {

        self.statusObserver = statusObserver
        self.serverInfoObserver = serverInfoObserver
        self.connectionErrorObserver = connectionErrorObserver
        self.connectivityIssuesObserver = connectivityIssuesObserver
        self.dataVolumeObserver = dataVolumeObserver
        self.knownFailureObserver = knownFailureObserver
        self.controllerErrorMessageObserver = controllerErrorMessageObserver
    }

    // MARK: - Forcing Refreshes

    public func forceRefresh() {

    }
}

#endif
