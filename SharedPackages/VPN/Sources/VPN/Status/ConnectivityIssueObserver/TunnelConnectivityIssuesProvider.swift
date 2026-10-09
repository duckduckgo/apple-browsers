//
//  TunnelConnectivityIssuesProvider.swift
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
import NetworkExtension

public final class TunnelConnectivityIssuesProvider {

    private static let responseTimeout: TimeInterval = 3

    private let sessionProvider: TunnelSessionProvider

    public init(sessionProvider: TunnelSessionProvider) {
        self.sessionProvider = sessionProvider
    }

    public func isExperiencingVPNConnectivityIssues() async -> Bool {
        guard let session = await sessionProvider.activeSession(), session.status == .connected else {
            return false
        }

        let response: ExtensionMessageBool? = try? await session.sendProviderMessage(.isHavingConnectivityIssues, timeout: Self.responseTimeout)
        return response?.value ?? false
    }
}
