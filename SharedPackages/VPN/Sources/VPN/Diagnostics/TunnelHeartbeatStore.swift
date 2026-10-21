//
//  TunnelHeartbeatStore.swift
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
import Persistence

/// Records a periodic "alive" timestamp from the packet tunnel so other VPN components
/// (notably the transparent proxy) can detect when the tunnel is no longer running.
public final class TunnelHeartbeatStore {

    public enum Keys {
        static let lastHeartbeatAt = "vpn.tunnel.last-heartbeat-at"
    }

    private let store: ThrowingKeyValueStoring
    private let dateGenerator: () -> Date

    public init(store: ThrowingKeyValueStoring, dateGenerator: @escaping () -> Date = Date.init) {
        self.store = store
        self.dateGenerator = dateGenerator
    }

    public func recordHeartbeat() {
        let timestamp = dateGenerator().timeIntervalSince1970
        try? store.set(timestamp, forKey: Keys.lastHeartbeatAt)
    }

    public var lastHeartbeat: Date? {
        guard let timestamp = (try? store.object(forKey: Keys.lastHeartbeatAt)) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    public func clear() {
        try? store.removeObject(forKey: Keys.lastHeartbeatAt)
    }
}
