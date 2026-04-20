//
//  VPNLeakCheckService.swift
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
import PixelKit

public actor VPNLeakCheckService {

    private let configuration: LeakCheckConfiguration
    private var egressIP: String
    private let httpClient: LeakCheckHTTPClient
    private let stunClient: LeakCheckSTUNClient
    private let wideEvent: WideEventManaging
    private let contextName: String

    private var currentCheck: Task<Void, Never>?
    private var lastCompletionDate: Date?

    public init(
        configuration: LeakCheckConfiguration = .default,
        egressIP: String,
        httpClient: LeakCheckHTTPClient,
        stunClient: LeakCheckSTUNClient,
        wideEvent: WideEventManaging,
        contextName: String
    ) {
        self.configuration = configuration
        self.egressIP = egressIP
        self.httpClient = httpClient
        self.stunClient = stunClient
        self.wideEvent = wideEvent
        self.contextName = contextName
    }

    public func runCheck(trigger: LeakCheckTrigger) async {
        guard currentCheck == nil else { return }
        if let last = lastCompletionDate, Date().timeIntervalSince(last) < configuration.cooldown {
            return
        }
        let task = Task { await executeCheck(trigger: trigger) }
        currentCheck = task
        await task.value
    }

    private func executeCheck(trigger: LeakCheckTrigger) async {
        defer {
            currentCheck = nil
            lastCompletionDate = Date()
        }

        let data = VPNIPLeakCheckWideEventData(
            trigger: trigger,
            contextData: WideEventContextData(name: contextName)
        )
        wideEvent.startFlow(data)

        let startDate = Date()
        let results = await probeAll()

        data.ipv4Http = classifyIPv4(results.ipv4Http)
        data.ipv4Https = classifyIPv4(results.ipv4Https)
        data.ipv4Stun = classifyIPv4(results.ipv4Stun)
        data.ipv6Http = classifyIPv6(results.ipv6Http)
        data.ipv6Https = classifyIPv6(results.ipv6Https)
        data.ipv6Stun = classifyIPv6(results.ipv6Stun)

        let ipv4Probes: [LeakCheckPerTestResult?] = [data.ipv4Http, data.ipv4Https, data.ipv4Stun]
        if ipv4Probes.contains(where: { $0?.status == .leak }),
           let leakedIP = firstLeakedIP(from: [results.ipv4Http, results.ipv4Https, results.ipv4Stun]) {
            data.ipv4LeakIPType = IPAddressClassifier.classify(leakedIP)
        }
        let ipv6Probes: [LeakCheckPerTestResult?] = [data.ipv6Http, data.ipv6Https, data.ipv6Stun]
        if ipv6Probes.contains(where: { $0?.status == .leak }),
           let leakedIP = firstLeakedIP(from: [results.ipv6Http, results.ipv6Https, results.ipv6Stun]) {
            data.ipv6LeakIPType = IPAddressClassifier.classify(leakedIP)
        }

        data.latencyMsBucketed = bucketedLatency(Date().timeIntervalSince(startDate))

        let status = determineStatus(data: data)
        if case .unknown(let reason) = status {
            data.statusReason = reason
        }

        wideEvent.completeFlow(data, status: status, onComplete: { _, _ in })
    }

    private struct ProbeResults {
        var ipv4Http: Result<String, Error>
        var ipv4Https: Result<String, Error>
        var ipv4Stun: Result<String, Error>
        var ipv6Http: Result<String, Error>
        var ipv6Https: Result<String, Error>
        var ipv6Stun: Result<String, Error>
    }

    private enum ProbeKey: Hashable {
        case ipv4Http, ipv4Https, ipv4Stun, ipv6Http, ipv6Https, ipv6Stun
    }

    private func probeAll() async -> ProbeResults {
        let config = configuration
        let http = httpClient
        let stun = stunClient

        var collected: [ProbeKey: Result<String, Error>] = [:]

        await withTaskGroup(of: (ProbeKey, Result<String, Error>).self) { group in
            group.addTask {
                (.ipv4Http, await Self.runProbe { try await http.fetchIP(host: config.host, port: config.httpPort, scheme: .http, ipVersion: .v4, timeout: config.httpTimeout) })
            }
            group.addTask {
                (.ipv4Https, await Self.runProbe { try await http.fetchIP(host: config.host, port: config.httpsPort, scheme: .https, ipVersion: .v4, timeout: config.httpTimeout) })
            }
            group.addTask {
                (.ipv4Stun, await Self.runProbe { try await stun.sendBindingRequest(host: config.host, port: config.stunPort, ipVersion: .v4, timeout: config.stunTimeout) })
            }
            group.addTask {
                (.ipv6Http, await Self.runProbe { try await http.fetchIP(host: config.host, port: config.httpPort, scheme: .http, ipVersion: .v6, timeout: config.httpTimeout) })
            }
            group.addTask {
                (.ipv6Https, await Self.runProbe { try await http.fetchIP(host: config.host, port: config.httpsPort, scheme: .https, ipVersion: .v6, timeout: config.httpTimeout) })
            }
            group.addTask {
                (.ipv6Stun, await Self.runProbe { try await stun.sendBindingRequest(host: config.host, port: config.stunPort, ipVersion: .v6, timeout: config.stunTimeout) })
            }
            for await item in group {
                collected[item.0] = item.1
            }
        }

        return ProbeResults(
            ipv4Http: collected[.ipv4Http] ?? .failure(CancellationError()),
            ipv4Https: collected[.ipv4Https] ?? .failure(CancellationError()),
            ipv4Stun: collected[.ipv4Stun] ?? .failure(CancellationError()),
            ipv6Http: collected[.ipv6Http] ?? .failure(CancellationError()),
            ipv6Https: collected[.ipv6Https] ?? .failure(CancellationError()),
            ipv6Stun: collected[.ipv6Stun] ?? .failure(CancellationError())
        )
    }

    private static func runProbe(_ operation: @Sendable () async throws -> String) async -> Result<String, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    private func classifyIPv4(_ result: Result<String, Error>) -> LeakCheckPerTestResult {
        switch result {
        case .success(let ip):
            return ip == egressIP ? .success : .leak
        case .failure(let error):
            return .error(error)
        }
    }

    private func classifyIPv6(_ result: Result<String, Error>) -> LeakCheckPerTestResult {
        switch result {
        case .success:
            return .leak
        case .failure:
            return .success
        }
    }

    private func firstLeakedIP(from results: [Result<String, Error>]) -> String? {
        for result in results {
            if case .success(let ip) = result, ip != egressIP { return ip }
        }
        return nil
    }

    private func bucketedLatency(_ seconds: TimeInterval) -> Int {
        let ms = Int(seconds * 1000)
        let rounded = ((ms + 500) / 1000) * 1000
        return min(rounded, 10_000)
    }

    private func determineStatus(data: VPNIPLeakCheckWideEventData) -> WideEventStatus {
        let probes: [LeakCheckPerTestResult?] = [
            data.ipv4Http, data.ipv4Https, data.ipv4Stun,
            data.ipv6Http, data.ipv6Https, data.ipv6Stun
        ]
        if probes.contains(where: { $0?.status == .leak }) {
            return .failure
        }
        if probes.contains(where: { $0?.status == .error }) {
            return .unknown(reason: "checks_errored")
        }
        return .success
    }
}
