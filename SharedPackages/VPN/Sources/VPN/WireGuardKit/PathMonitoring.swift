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
    var statusUpdateHandler: ((NWPath.Status) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}

final class NWPathStatusMonitor: PathMonitoring {
    private let monitor = NWPathMonitor()
    var statusUpdateHandler: ((NWPath.Status) -> Void)?

    func start(queue: DispatchQueue) {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.statusUpdateHandler?(path.status)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
