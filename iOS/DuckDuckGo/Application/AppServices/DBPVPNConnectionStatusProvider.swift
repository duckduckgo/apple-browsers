//
//  DBPVPNConnectionStatusProvider.swift
//  DuckDuckGo
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

import DataBrokerProtectionCore
import VPN

/// Reports the VPN connection state to PIR jobs. VPN bypass isn't available on iOS,
/// so the bypass members report it as unsupported and changes are ignored.
final class DBPVPNConnectionStatusProvider: VPNBypassFeatureProvider {

    private let connectionObserver: ConnectionStatusObserver

    init(connectionObserver: ConnectionStatusObserver) {
        self.connectionObserver = connectionObserver
    }

    // MARK: - VPNConnectionStatusThroughIPCProvider

    /// The observer loads the current tunnel status when it's created, so there is nothing to set up.
    func setUp() {}

    var connectionStatus: String {
        connectionObserver.recentValue.description
    }

    // MARK: - VPNBypassServiceProvider

    var isEnabled: Bool { false }

    var bypassStatus: VPNBypassStatus { .unsupported }

    var isOnboardingShown: Bool {
        get { false }
        set {}
    }

    func applyVPNBypass(_ bypass: Bool) {}
}
