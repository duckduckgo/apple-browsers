//
//  XPCErrorSanitizer.swift
//  VPN
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public struct XPCErrorSanitizer {
    
    public static func sanitize(_ error: Error) -> Error {
        let nsError = error as NSError
        return isXPCSafe(nsError) ? error : PacketTunnelProvider.TunnelError.xpcIncompatibleError(underlyingError: error)
    }

    static func isXPCSafe(_ error: NSError) -> Bool {
        do {
            _ = try NSKeyedArchiver.archivedData(withRootObject: error, requiringSecureCoding: true)
            return true
        } catch {
            return false
        }
    }

}

extension Error {
    func sanitizedForXPC() -> Error {
        return XPCErrorSanitizer.sanitize(self)
    }
}

extension PacketTunnelProvider.TunnelError {
    var sanitizedForXPC: PacketTunnelProvider.TunnelError {
        switch self {
        case .couldNotGenerateTunnelConfiguration(let internalError):
            return .couldNotGenerateTunnelConfiguration(internalError: internalError.sanitizedForXPC())
        case .vpnAccessRevoked(let underlyingError):
            return .vpnAccessRevoked(underlyingError.sanitizedForXPC())
        case .startingTunnelWithoutAuthToken(let internalError):
            return .startingTunnelWithoutAuthToken(internalError: internalError?.sanitizedForXPC())
        default:
            let nsError = self as NSError
            return XPCErrorSanitizer.isXPCSafe(nsError) ? self : .xpcIncompatibleError(underlyingError: self)
        }
    }
}
