//
//  ConnectionSessionUtilities.swift
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
import NetworkExtension

/// These are only usable from the App that owns the tunnel.
///
public class ConnectionSessionUtilities {

    /// Retrieves a session from a `NEVPNStatusDidChange` notification.
    ///
    public static func session(from notification: Notification) -> NETunnelProviderSession? {
        guard let session = (notification.object as? NETunnelProviderSession),
              session.manager is NETunnelProviderManager else {
            return nil
        }

        return session
    }

}

public extension NETunnelProviderSession {

    // MARK: - ExtensionMessage

    func sendProviderMessage(_ message: ExtensionMessage,
                             responseHandler: @escaping () -> Void) throws {
        try sendProviderMessage(message.rawValue) { _ in
            responseHandler()
        }
    }

    func sendProviderMessage<T: RawRepresentable>(_ message: ExtensionMessage,
                                                  responseHandler: @escaping (T?) -> Void) throws where T.RawValue == Data {
        try sendProviderMessage(message.rawValue) { response in
            responseHandler(response.flatMap(T.init(rawValue:)))
        }
    }

    func sendProviderRequest(_ request: ExtensionRequest) async throws {
        try await sendProviderMessage(.request(request))
    }

    func sendProviderRequest<T: RawRepresentable>(_ request: ExtensionRequest) async throws -> T? where T.RawValue == Data {

        try await sendProviderMessage(.request(request))
    }

    func sendProviderMessage(_ message: ExtensionMessage) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try sendProviderMessage(message) {
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func sendProviderMessage<T: RawRepresentable>(_ message: ExtensionMessage) async throws -> T? where T.RawValue == Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try sendProviderMessage(message) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
