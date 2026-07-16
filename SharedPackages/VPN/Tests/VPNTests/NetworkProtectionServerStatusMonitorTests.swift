//
//  NetworkProtectionServerStatusMonitorTests.swift
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

import XCTest
import VPNTestUtils
@testable import VPN

final class NetworkProtectionServerStatusMonitorTests: XCTestCase {

    /// The monitor's periodic task must not retain the monitor, otherwise the monitor leaks
    /// for the lifetime of the (forever-repeating) task whenever its owner is released without
    /// first calling `stop()`. Deallocating the owner should be enough to tear it down.
    func testStartDoesNotRetainMonitor() async {
        weak var weakMonitor: NetworkProtectionServerStatusMonitor?

        // Allocate and start the monitor in a nested scope so its strong reference is gone
        // by the time we assert. Deliberately never call stop(): the monitor must still
        // deallocate once the local strong reference goes away.
        func startMonitorInScope() async {
            let monitor = NetworkProtectionServerStatusMonitor(
                networkClient: MockNetworkProtectionClient(),
                tokenHandler: SubscriptionTokenHandlingMock()
            )
            weakMonitor = monitor
            await monitor.start(serverName: "test-server") { _ in }
        }
        await startMonitorInScope()

        XCTAssertNil(weakMonitor, "Monitor leaked — its periodic task is retaining self strongly")
    }
}
