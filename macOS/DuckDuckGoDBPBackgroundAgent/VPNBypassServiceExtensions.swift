//
//  VPNBypassServiceExtensions.swift
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
import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import NetworkProtectionProxy
import NetworkProtectionIPC

extension VPNBypassService {
    public convenience init() {
        self.init(dbpSettings: DataBrokerProtectionSettings(defaults: .dbp),
                  backgroundAgentBundleId: Bundle.main.dbpBackgroundAgentBundleId,
                  proxySettings: TransparentProxySettings(defaults: .netP))
    }

    public var isSupported: Bool {
#if APPSTORE
#if NETP_SYSTEM_EXTENSION
        return true
#else
        return false
#endif
#else
        return true
#endif
    }
}

extension VPNBypassService: @retroactive VPNConnectionStatusThroughIPCProvider {
    public func setUp() {
        VPNControllerXPCClient.shared.register { _ in }
    }

    public var connectionStatus: String {
        VPNControllerXPCClient.shared.connectionStatusObserver.recentValue.description
    }
}

public extension VPNControllerXPCClient {
    static let shared = VPNControllerXPCClient()

    convenience init() {
        self.init(machServiceName: Bundle.main.vpnMenuAgentBundleId)
    }
}
