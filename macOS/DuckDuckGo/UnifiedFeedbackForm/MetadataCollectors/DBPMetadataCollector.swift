//
//  DBPMetadataCollector.swift
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
import VPN
import NetworkProtectionIPC
import DataBrokerProtection_macOS
import DataBrokerProtectionCore

struct DBPFeedbackMetadata: UnifiedFeedbackMetadata {
    let vpnConnectionState: String
    let vpnBypassStatus: String

    enum CodingKeys: String, CodingKey {
        case vpnConnectionState = "vpn_connection_state"
        case vpnBypassStatus = "vpn_bypass"
    }
}

final class DefaultDBPMetadataCollector: UnifiedMetadataCollector {
    private let vpnIPCClient: VPNControllerXPCClient
    private let vpnBypassService: VPNBypassServiceProvider

    init() {
        let ipcClient = VPNControllerXPCClient.shared
        ipcClient.register { _ in }

        self.vpnIPCClient = ipcClient
        self.vpnBypassService = VPNBypassService()
    }

    func collectMetadata() async -> DBPFeedbackMetadata {
        DBPFeedbackMetadata(
            vpnConnectionState: vpnIPCClient.connectionStatusObserver.recentValue.description,
            vpnBypassStatus: vpnBypassService.bypassStatus.rawValue
        )
    }
}
