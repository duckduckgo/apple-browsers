//
//  NetworkProtectionServerStatusMonitor.swift
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
import Network
import Common
import Combine
import os.log

public actor NetworkProtectionServerStatusMonitor {

    public enum ServerStatusResult {
        case serverMigrationRequested
        case error(Error)

        var shouldMigrate: Bool {
            switch self {
            case .serverMigrationRequested: return true
            case .error: return false
            }
        }
    }

    private static let monitoringInterval: TimeInterval = .minutes(5)

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    var isStarted: Bool {
        task?.isCancelled == false
    }

    private let networkClient: NetworkProtectionClient
    private let tokenHandler: any SubscriptionTokenHandling

    // MARK: - Init & deinit

    init(networkClient: NetworkProtectionClient, tokenHandler: any SubscriptionTokenHandling) {
        self.networkClient = networkClient
        self.tokenHandler = tokenHandler

        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        task?.cancel()

        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
    }

    // MARK: - Start/Stop monitoring

    public func start(serverName: String, callback: @escaping (ServerStatusResult) -> Void) {
        Logger.networkProtectionServerStatusMonitor.log("⚫️ Starting server status monitor for \(serverName, privacy: .public)")

        task = Task.periodic(delay: Self.monitoringInterval, interval: Self.monitoringInterval) {
            let result = await self.checkServerStatus(for: serverName)

            switch result {
            case .success(let serverStatus):
                if serverStatus.shouldMigrate {
                    Logger.networkProtectionMemory.log("⚫️ Initiating server migration away from \(serverName, privacy: .public)")
                    callback(.serverMigrationRequested)
                } else {
                    Logger.networkProtectionMemory.log("⚫️ No migration requested for \(serverName, privacy: .public)")
                }
            case .failure(let error):
                Logger.networkProtectionMemory.error("⚫️ Error retrieving server status: \(error.localizedDescription, privacy: .public)")
                callback(.error(error))
            }
        }
    }

    public func stop() {
        Logger.networkProtectionMemory.log("⚫️ Stopping server status monitor")

        task?.cancel()
        task = nil
    }

    // MARK: - Server Status Check

    private func checkServerStatus(for serverName: String) async -> Result<NetworkProtectionServerStatus, NetworkProtectionClientError> {
        guard let accessToken = try? await VPNAuthTokenBuilder.getVPNAuthToken(from: tokenHandler) else {
            Logger.networkProtection.fault("Failed to check server status due to lack of access token")
            return .failure(.invalidAuthToken)
        }
        return await networkClient.getServerStatus(authToken: accessToken, serverName: serverName)
    }

}
