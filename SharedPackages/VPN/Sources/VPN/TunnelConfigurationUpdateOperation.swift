//
//  TunnelConfigurationUpdateOperation.swift
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

@MainActor
enum TunnelConfigurationUpdateOperation {

    static func run(
        reassert: Bool,
        generateTunnelConfiguration: () async throws -> TunnelConfiguration,
        stopMonitors: () async -> Void,
        updateAdapterConfiguration: (TunnelConfiguration) async throws -> Void,
        handleAdapterStarted: () async throws -> Void,
        handleFailure: (Error) async -> Bool,
        restartMonitorsAfterFailure: () async -> Void
    ) async throws {
        var didStopMonitors = false

        do {
            let tunnelConfiguration = try await generateTunnelConfiguration()

            if reassert {
                await stopMonitors()
                didStopMonitors = true
            }

            try await updateAdapterConfiguration(tunnelConfiguration)

            if reassert {
                try await handleAdapterStarted()
            }
        } catch {
            let didCancelTunnel = await handleFailure(error)
            if reassert, didStopMonitors, !didCancelTunnel {
                await restartMonitorsAfterFailure()
            }
            throw error
        }
    }
}
