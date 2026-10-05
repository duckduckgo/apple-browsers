//
//  NetworkPathMonitor.swift
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
import Network

public struct NetworkPathState: Equatable, Sendable {
    public let networkType: NetworkSignals.NetworkType
    public let isConstrained: Bool

    public init(networkType: NetworkSignals.NetworkType, isConstrained: Bool) {
        self.networkType = networkType
        self.isConstrained = isConstrained
    }
}

public protocol NetworkPathProviding: AnyObject {
    var currentPathState: NetworkPathState { get }
}

public final class NetworkPathMonitor: NetworkPathProviding {

    private let monitor: NWPathMonitor

    public init(monitor: NWPathMonitor = NWPathMonitor(),
                queue: DispatchQueue = DispatchQueue(label: "com.duckduckgo.network-signals.path-monitor")) {
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public var currentPathState: NetworkPathState {
        let path = monitor.currentPath
        return NetworkPathState(networkType: networkType(for: path), isConstrained: path.isConstrained)
    }

    private func networkType(for path: NWPath) -> NetworkSignals.NetworkType {
        guard path.status == .satisfied else {
            return .unavailable
        }

        if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        }

        if path.usesInterfaceType(.cellular) {
            return .cellular
        }

        return .unknown
    }
}
