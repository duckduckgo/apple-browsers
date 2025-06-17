//
//  NEProviderStopReason+DebugDescription.swift
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

import NetworkExtension

extension NEProviderStopReason: @retroactive CustomDebugStringConvertible {

    public var debugDescription: String {
        switch self {
        case .none:
            return "No specific reason"
        case .userInitiated:
            return "User stopped the provider"
        case .providerFailed:
            return "Provider failed"
        case .noNetworkAvailable:
            return "No network connectivity"
        case .unrecoverableNetworkChange:
            return "Unrecoverable network change"
        case .providerDisabled:
            return "Provider was disabled"
        case .authenticationCanceled:
            return "Authentication canceled"
        case .configurationFailed:
            return "Configuration failed"
        case .idleTimeout:
            return "Idle timeout"
        case .configurationDisabled:
            return "Configuration disabled"
        case .configurationRemoved:
            return "Configuration removed"
        case .superceded:
            return "Superceded by a high-priority configuration"
        case .userLogout:
            return "User logged out"
        case .userSwitch:
            return "User switched"
        case .connectionFailed:
            return "Connection failed"
        case .sleep:
            return "Device went to sleep"
        case .appUpdate:
            return "App update in progress"
        case .internalError:
            return "Internal error"
        @unknown default:
            return "Unknown stop reason (\(self.rawValue))"
        }
    }
}
