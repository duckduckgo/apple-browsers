//
//  PathMonitoring.swift
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
import Network

/// Status Snapshot of the current network path
struct VPNNetworkPathSnapshot: Equatable {

    let status: NWPath.Status

    /// `nil` when the path is not backed by wifi, ethernet or cellular.
    let connectionType: NetworkConnectionType?

    let anonymousDescription: String

    init(status: NWPath.Status, connectionType: NetworkConnectionType?, anonymousDescription: String) {
        self.status = status
        self.connectionType = connectionType
        self.anonymousDescription = anonymousDescription
    }

    /// A handshake gap only indicates tunnel failure when the network is up
    var isReachable: Bool {
        connectionType != nil && status == .satisfied
    }
}

protocol PathMonitoring: AnyObject {
    var pathUpdateHandler: ((NWPath.Status) -> Void)? { get set }

    /// The most recent path, or `nil` before the monitor has started.
    var currentPathSnapshot: VPNNetworkPathSnapshot? { get }

    func start(queue: DispatchQueue)
    func cancel()
}

/// NWPathMonitor emits `NWPath` objects upon path changes, but we cannot instantiate `NWPath` ourselves directly due to no public initializer.
/// Since the VPN only cares about the path status, the `PathMonitoring` protocol emits those directly and the `PathMonitor` class serves as
/// a bridge between the two.
final class PathMonitor: PathMonitoring {

    private let monitor: NWPathMonitor

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    var pathUpdateHandler: ((NWPath.Status) -> Void)? {
        didSet {
            if let handler = pathUpdateHandler {
                monitor.pathUpdateHandler = { path in
                    handler(path.status)
                }
            } else {
                monitor.pathUpdateHandler = nil
            }
        }
    }

    /// Read through rather than cached: no lock, and never staler than the path.
    var currentPathSnapshot: VPNNetworkPathSnapshot? {
        Self.snapshot(from: monitor.currentPath)
    }

    func start(queue: DispatchQueue) {
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }

    private static func snapshot(from path: NWPath) -> VPNNetworkPathSnapshot {
        VPNNetworkPathSnapshot(status: path.status,
                               connectionType: NetworkConnectionType(nwPath: path),
                               anonymousDescription: path.anonymousDescription)
    }
}
