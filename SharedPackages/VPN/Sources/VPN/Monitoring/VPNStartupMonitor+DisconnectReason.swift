//
//  VPNStartupMonitor+DisconnectReason.swift
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

extension VPNStartupMonitor.StartupError {
    public var disconnectReasonDescription: String? {
        guard let reason = disconnectReason else { return nil }
        // Omitting userInfo lets Foundation display the domain and code even for errors with custom descriptions.
        return NSError(domain: reason.domain, code: reason.code).localizedDescription
    }

    public var disconnectReason: (domain: String, code: Int)? {
        guard case .startTunnelDisconnectedSilently(let underlyingError?) = self else { return nil }

        let disconnectError = underlyingError as NSError
        let reason = XPCErrorSanitizer.originalDomainAndCode(of: disconnectError)
        if reason.domain == PacketTunnelProvider.TunnelError.errorDomain,
           reason.code == PacketTunnelProvider.TunnelError.Code.otherTunnelStartError.rawValue,
           let cause = disconnectError.userInfo[NSUnderlyingErrorKey] as? Error {
            return XPCErrorSanitizer.originalDomainAndCode(of: cause as NSError)
        }
        return reason
    }
}
