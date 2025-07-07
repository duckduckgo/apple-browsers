//
//  NetworkProtectionStatusReporter.swift
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

import Combine
import NetworkExtension
import Common

/// Classes that implement this protocol are in charge of relaying status changes.
///
public protocol NetworkProtectionStatusReporter {
    var statusObserver: ConnectionStatusObserver { get }
    var serverInfoObserver: ConnectionServerInfoObserver { get }
    var connectionErrorObserver: ConnectionErrorObserver { get }
    var connectivityIssuesObserver: ConnectivityIssueObserver { get }
    var controllerErrorMessageObserver: ControllerErrorMesssageObserver { get }
    var dataVolumeObserver: DataVolumeObserver { get }
    var knownFailureObserver: KnownFailureObserver { get }
}

/// Convenience struct used to relay server info updates through a reporter.
///
public struct NetworkProtectionStatusServerInfo: Codable, Equatable {
    public static let unknown = NetworkProtectionStatusServerInfo(serverLocation: nil, serverAddress: nil)

    /// The server location.  A `nil` location means unknown
    ///
    public let serverLocation: NetworkProtectionServerInfo.ServerAttributes?

    /// The server address.  A `nil` address means unknown.
    ///
    public let serverAddress: String?

    public init(serverLocation: NetworkProtectionServerInfo.ServerAttributes?, serverAddress: String?) {
        self.serverLocation = serverLocation
        self.serverAddress = serverAddress
    }
}

#if os(macOS)

/// This is the default status reporter.
///
public final class DefaultNetworkProtectionStatusReporter: NetworkProtectionStatusReporter {

    // MARK: - Notifications

    private let distributedNotificationCenter: DistributedNotificationCenter

    // MARK: - Publishers

    public let statusObserver: ConnectionStatusObserver
    public let serverInfoObserver: ConnectionServerInfoObserver
    public let connectionErrorObserver: ConnectionErrorObserver
    public let connectivityIssuesObserver: ConnectivityIssueObserver
    public let controllerErrorMessageObserver: ControllerErrorMesssageObserver
    public let dataVolumeObserver: DataVolumeObserver
    public let knownFailureObserver: KnownFailureObserver

    // MARK: - Init & deinit

    public init(statusObserver: ConnectionStatusObserver,
                serverInfoObserver: ConnectionServerInfoObserver,
                connectionErrorObserver: ConnectionErrorObserver,
                connectivityIssuesObserver: ConnectivityIssueObserver,
                controllerErrorMessageObserver: ControllerErrorMesssageObserver,
                dataVolumeObserver: DataVolumeObserver,
                knownFailureObserver: KnownFailureObserver,
                distributedNotificationCenter: DistributedNotificationCenter = .default()) {

        self.statusObserver = statusObserver
        self.serverInfoObserver = serverInfoObserver
        self.connectionErrorObserver = connectionErrorObserver
        self.connectivityIssuesObserver = connectivityIssuesObserver
        self.controllerErrorMessageObserver = controllerErrorMessageObserver
        self.dataVolumeObserver = dataVolumeObserver
        self.knownFailureObserver = knownFailureObserver
        self.distributedNotificationCenter = distributedNotificationCenter
    }
}

#endif
