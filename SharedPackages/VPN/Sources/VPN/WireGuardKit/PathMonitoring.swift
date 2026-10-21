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

protocol PathMonitoring: AnyObject {
    var pathUpdateHandler: ((NWPath.Status) -> Void)? { get set }
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

    func start(queue: DispatchQueue) {
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
