//
//  FailureRecoveryHandler.swift
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
import Common
import os.log

public enum FailureRecoveryStep {
    public enum ServerHealth {
        case healthy
        case unhealthy
    }

    case started
    case completed(ServerHealth)
    case failed(_ error: Error)
}

protocol FailureRecoveryHandling {
    func attemptRecovery(
        to lastConnectedServer: NetworkProtectionServer,
        excludeLocalNetworks: Bool,
        dnsSettings: NetworkProtectionDNSSettings,
        updateConfig: @escaping (NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult) async throws -> Void
    ) async

    func stop() async
}

private enum FailureRecoveryResult: Error {
    case noRecoveryNecessary
    case updateConfiguration(NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult)
}

actor FailureRecoveryHandler: FailureRecoveryHandling {

    struct RetryConfig {
        let times: Int
        let initialDelay: TimeInterval
        let maxDelay: TimeInterval
        let factor: Double

        static var `default` = RetryConfig(
            times: 5,
            initialDelay: .seconds(30),
            maxDelay: .minutes(5),
            factor: 2.0
        )
    }

    private let deviceManager: NetworkProtectionDeviceManagement
    private weak var reassertingControl: Reasserting?
    private let retryConfig: RetryConfig
    private let eventHandler: (FailureRecoveryStep) -> Void

    private var task: Task<Void, Never>? {
        willSet {
            task?.cancel()
        }
    }

    init(deviceManager: NetworkProtectionDeviceManagement, reassertingControl: Reasserting, retryConfig: RetryConfig = .default, eventHandler: @escaping (FailureRecoveryStep) -> Void) {
        self.deviceManager = deviceManager
        self.reassertingControl = reassertingControl
        self.retryConfig = retryConfig
        self.eventHandler = eventHandler
    }

    func attemptRecovery(
        to lastConnectedServer: NetworkProtectionServer,
        excludeLocalNetworks: Bool,
        dnsSettings: NetworkProtectionDNSSettings,
        updateConfig: @escaping (NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult) async throws -> Void
    ) async {
        reassertingControl?.startReasserting()
        defer {
            reassertingControl?.stopReasserting()
        }
        let eventHandler = eventHandler
        await incrementalPeriodicChecks(retryConfig) { [weak self] in
            guard let self else { return }
            eventHandler(.started)
            do {
                let result = try await makeRecoveryAttempt(
                    to: lastConnectedServer,
                    excludeLocalNetworks: excludeLocalNetworks,
                    dnsSettings: dnsSettings)
                switch result {
                case .noRecoveryNecessary:
                    eventHandler(.completed(.healthy))
                case .updateConfiguration(let generateConfigResult):
                    try await updateConfig(generateConfigResult)
                    eventHandler(.completed(.unhealthy))
                }
            } catch let error as NetworkProtectionErrorConvertible {
                eventHandler(.failed(error.networkProtectionError))
                throw error.networkProtectionError
            } catch {
                eventHandler(.failed(error))
                throw error
            }
        }
    }

    func stop() {
        task = nil
    }

    private func makeRecoveryAttempt(
        to lastConnectedServer: NetworkProtectionServer,
        excludeLocalNetworks: Bool,
        dnsSettings: NetworkProtectionDNSSettings) async throws -> FailureRecoveryResult {

        let serverSelectionMethod: NetworkProtectionServerSelectionMethod = .failureRecovery(serverName: lastConnectedServer.serverName)
        let configurationResult: NetworkProtectionDeviceManagement.GenerateTunnelConfigurationResult

        configurationResult = try await deviceManager.generateTunnelConfiguration(
            resolvedSelectionMethod: serverSelectionMethod,
            excludeLocalNetworks: excludeLocalNetworks,
            dnsSettings: dnsSettings,
            regenerateKey: false
        )
        Logger.networkProtectionTunnelFailureMonitor.log("🟢 Failure recovery fetched new config.")

        let newServer = configurationResult.server

        Logger.networkProtection.log("""
        🟢 Failure recovery - originalServerName: \(lastConnectedServer.serverName, privacy: .public)
        newServerName: \(newServer.serverName, privacy: .public)
        originalAllowedIPs: \(String(describing: lastConnectedServer.allowedIPs), privacy: .public)
        newAllowedIPs: \(String(describing: newServer.allowedIPs), privacy: .public)
        """)

        guard lastConnectedServer.shouldReplace(with: newServer) else {
            Logger.networkProtectionTunnelFailureMonitor.log("🟢 Server failure recovery not necessary.")
            return .noRecoveryNecessary
        }

        return .updateConfiguration(configurationResult)
    }

    private func incrementalPeriodicChecks(
        _ config: RetryConfig,
        action: @escaping () async throws -> Void
    ) async {
        let task = Task(priority: .background) {
            var currentDelay = config.initialDelay
            var count = 0
            repeat {
                do {
                    try Task.checkCancellation()
                } catch {
                    // Task cancelled
                    return
                }
                do {
                    try await action()
                    Logger.networkProtectionTunnelFailureMonitor.log("🟢 Failure recovery success!")
                    return
                } catch {
                    Logger.networkProtectionTunnelFailureMonitor.log("🟢 Failure recovery failed. Retrying...")
                }
                do {
                    try await Task.sleep(interval: currentDelay)
                } catch {
                    // Task cancelled
                    return
                }
                count += 1
                currentDelay = min((currentDelay * config.factor), config.maxDelay)
            } while count < config.times
        }
        self.task = task
        await task.value
    }
}

private extension NetworkProtectionServer {
    func shouldReplace(with newServer: NetworkProtectionServer) -> Bool {
        guard serverName == newServer.serverName else {
            return true
        }

        guard let lastAllowedIPs = allowedIPs,
              let newAllowedIPs = newServer.allowedIPs,
              Set(lastAllowedIPs) == Set(newAllowedIPs) else {
            return true
        }

        return false
    }
}
