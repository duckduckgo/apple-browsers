//
//  NEPacketTunnelProvider+TunnelInterface.swift
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
import NetworkExtension

extension NEPacketTunnelProvider {

    /// Resolves the tunnel's virtual `NWInterface`.
    ///
    /// Uses `virtualInterface` on iOS 18 / macOS 15 and later, where the system surfaces the tunnel
    /// interface directly and is trusted as the source of truth. On earlier OS versions — or if
    /// `virtualInterface` is unexpectedly nil — falls back to looking up the interface by name
    /// through `NWPathMonitor`.
    ///
    /// `fallbackInterfaceName` is only consulted on the fallback path; on iOS 18 / macOS 15+ the
    /// system property is the source of truth and the parameter is ignored.
    ///
    /// On the fallback path the resolved interface is validated to be a `utun`. If it isn't, the
    /// tunnel was likely rebound underneath us and this is no longer the tunnel interface, so we
    /// report `.unexpectedInterface` rather than handing back a non-tunnel interface to probe.
    func resolveTunnelInterface(fallbackInterfaceName: String?) async -> LeakCheckTunnelInterface {
        if #available(iOS 18.0, macOS 15.0, *) {
            if let interface = virtualInterface {
                return .resolved(interface)
            }
        }

        guard let fallbackInterfaceName else {
            return .unavailable
        }

        guard let interface = await Self.findInterface(named: fallbackInterfaceName) else {
            return .unavailable
        }

        guard Self.isTunnelInterfaceName(interface.name) else {
            return .unexpectedInterface
        }

        return .resolved(interface)
    }

    static func isTunnelInterfaceName(_ interfaceName: String) -> Bool {
        interfaceName.hasPrefix("utun")
    }

    private static func findInterface(named interfaceName: String) async -> NWInterface? {
        let monitor = NWPathMonitor()
        let paths = AsyncStream<Network.NWPath> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
                continuation.finish()
            }

            continuation.onTermination = { _ in
                monitor.cancel()
            }

            monitor.start(queue: .global(qos: .utility))
        }

        for await path in paths {
            return path.availableInterfaces.first(where: { $0.name == interfaceName })
        }

        return nil
    }
}
