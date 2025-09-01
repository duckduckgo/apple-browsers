//
//  DBPMetadataCollector.swift
//  DuckDuckGo
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
import NetworkExtension
import Network

struct DBPFeedbackMetadata: UnifiedFeedbackMetadata {
    let vpnConnectionState: String

    enum CodingKeys: String, CodingKey {
        case vpnConnectionState = "vpn_connection_state"
    }
    
    func toPrettyPrintedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let encodedMetadata = try? encoder.encode(self) else {
            assertionFailure("Failed to encode metadata")
            return nil
        }

        return String(data: encodedMetadata, encoding: .utf8)
    }
}

final class DefaultDBPMetadataCollector: UnifiedMetadataCollector {
    private let vpnStatusObserver: ConnectionStatusObserver

    init(vpnStatusObserver: ConnectionStatusObserver = AppDependencyProvider.shared.connectionObserver) {
        self.vpnStatusObserver = vpnStatusObserver
    }

    func collectMetadata() async -> DBPFeedbackMetadata? {
        DBPFeedbackMetadata(
            vpnConnectionState: String(describing: vpnStatusObserver.recentValue)
        )
    }
}
