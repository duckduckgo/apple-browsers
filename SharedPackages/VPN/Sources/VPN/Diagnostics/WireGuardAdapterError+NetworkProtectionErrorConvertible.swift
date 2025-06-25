//
//  WireGuardAdapterError+NetworkProtectionErrorConvertible.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

extension WireGuardAdapterError: NetworkProtectionErrorConvertible {
    var networkProtectionError: NetworkProtectionError {
        switch self {
        case .cannotLocateTunnelFileDescriptor:
            return .wireGuardCannotLocateTunnelFileDescriptor
        case .invalidState(let reason):
            return .wireGuardInvalidState(reason: reason.rawValue)
        case .dnsResolution:
            return .wireGuardDnsResolution
        case .setNetworkSettings(let error):
            return .wireGuardSetNetworkSettings(error)
        case .startWireGuardBackend(let error):
            return .startWireGuardBackend(error)
        case .setWireguardConfig(let error):
            return .setWireguardConfig(error)
        }
    }
}
