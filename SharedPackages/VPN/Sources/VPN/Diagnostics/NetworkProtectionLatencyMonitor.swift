//
//  NetworkProtectionLatencyMonitor.swift
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
import Network
import os.log
import Combine

public actor NetworkProtectionLatencyMonitor {
    public enum ConnectionQuality: String {
        case terrible
        case poor
        case moderate
        case good
        case excellent
        case unknown

        init(average: TimeInterval) {
            switch average {
            case 300...:
                self = .terrible
            case 200..<300:
                self = .poor
            case 50..<200:
                self = .moderate
            case 20..<50:
                self = .good
            case 0..<20:
                self = .excellent
            default:
                self = .unknown
            }
        }
    }

    public enum Result {
        case error
        case quality(ConnectionQuality)
    }

    private static let reportThreshold: TimeInterval = .minutes(10)
    private static let measurementInterval: TimeInterval = .seconds(5)
    private static let pingTimeout: TimeInterval = .seconds(1)

    private static let unknownLatency: TimeInterval = -1

    private let latencySubject = PassthroughSubject<TimeInterval, Never>()

    private var latencyCancellable: AnyCancellable?

    private var task: Task<Never, Error>? {
        willSet {
            task?.cancel()
        }
    }

    var isStarted: Bool {
        task?.isCancelled == false
    }

    private var lastLatencyReported: Date = .distantPast

    // MARK: - Init & deinit

    init() {
        Logger.networkProtectionMemory.debug("[+] \(String(describing: self), privacy: .public)")
    }

    deinit {
        task?.cancel()

        Logger.networkProtectionMemory.debug("[-] \(String(describing: self), privacy: .public)")
    }

    // MARK: - Start/Stop monitoring

    public func start(serverIP: IPv4Address, callback: @escaping (Result) -> Void) {
        Logger.networkProtectionLatencyMonitor.log("⚫️ Starting latency monitor")

        lastLatencyReported = Date()

        latencyCancellable = latencySubject.eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .scan(ExponentialGeometricAverage()) { measurements, latency in
                if latency >= 0 {
                    measurements.addMeasurement(latency)
                    Logger.networkProtectionMemory.debug("⚫️ Latency: \(latency, privacy: .public) milliseconds")
                } else {
                    callback(.error)
                }

                Logger.networkProtectionMemory.debug("⚫️ Average: \(measurements.average, privacy: .public) milliseconds")

                return measurements
            }
            .map { ConnectionQuality(average: $0.average) }
            .sink { quality in
                Task { [weak self] in
                    let now = Date()
                    if let self,
                       await now.timeIntervalSince1970 - self.lastLatencyReported.timeIntervalSince1970 >= Self.reportThreshold {
                        callback(.quality(quality))
                        await self.updateLastLatencyReported(date: now)
                    }
                }
            }

        task = Task.periodic(interval: Self.measurementInterval) { [weak self] in
            await self?.measureLatency(to: serverIP)
        }
    }

    public func stop() {
        Logger.networkProtectionLatencyMonitor.log("⚫️ Stopping latency monitor")

        latencyCancellable = nil
        task?.cancel() // Just making extra sure in case it's detached
        task = nil
    }

    private func updateLastLatencyReported(date: Date) {
        lastLatencyReported = date
    }

    // MARK: - Latency monitor

    private func measureLatency(to ip: IPv4Address) async {
        Logger.networkProtectionLatencyMonitor.debug("⚫️ Pinging \(ip.debugDescription, privacy: .public)")

        let result = await Pinger(ip: ip, timeout: Self.pingTimeout).ping()

        switch result {
        case .success(let pingResult):
            latencySubject.send(pingResult.time * 1000)
        case .failure(let error):
            Logger.networkProtectionMemory.error("⚫️ Ping error: \(error.localizedDescription, privacy: .public)")
            latencySubject.send(Self.unknownLatency)
        }
    }

    public func simulateLatency(_ timeInterval: TimeInterval) {
        latencySubject.send(timeInterval)
    }
}

public final class ExponentialGeometricAverage {
    private static let decayConstant = 0.1
    private let cutover = ceil(1 / decayConstant)

    private var count = TimeInterval(0)
    private var value = TimeInterval(-1)

    public var average: TimeInterval {
        value
    }

    public func addMeasurement(_ measurement: TimeInterval) {
        let keepConstant = 1 - Self.decayConstant

        if count > cutover {
            value = exp(keepConstant * log(value) + Self.decayConstant * log(measurement))
        } else if count > 0 {
            let retained: Double = keepConstant * count / (count + 1.0)
            let newcomer = 1.0 - retained
            value = exp(retained * log(value) + newcomer * log(measurement))
        } else {
            value = measurement
        }
        count += 1
    }

    public func reset() {
        value = -1.0
        count = 0
    }
}
