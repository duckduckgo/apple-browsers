//
//  WakeConnectivityMonitor.swift
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

/// Records failed connectivity after wake using the existing tunnel probes, regardless of cause.
public final class WakeConnectivityMonitor: @unchecked Sendable {
    private enum State {
        case asleep
        case checking(failureCount: Int)
        case finished
    }

    private let lock = NSLock()
    private var state: State = .asleep
    private var generation: UInt64 = 0
    private var wakeDate: Date?
    private let now: () -> Date
    private let reportQueue: DispatchQueue
    private let pixelFiring: PixelKitFiring?

    public convenience init(pixelFiring: PixelKitFiring? = PixelKit.shared) {
        self.init(pixelFiring: pixelFiring, now: Date.init,
                  reportQueue: DispatchQueue(label: "com.duckduckgo.vpn.wake-connectivity-pixel"))
    }

    init(pixelFiring: PixelKitFiring?, now: @escaping () -> Date, reportQueue: DispatchQueue) {
        self.pixelFiring = pixelFiring
        self.now = now
        self.reportQueue = reportQueue
    }

    public func wake(isEligible: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard isEligible else {
            cancelInLock()
            state = .finished
            return
        }
        guard case .asleep = state else { return }
        wakeDate = now()
        state = .checking(failureCount: 0)
    }

    public func sleep() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        state = .asleep
        wakeDate = nil
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelInLock()
    }

    public func connectionTestCompleted(isConnected: Bool, startedAt: Date) {
        var reportGeneration: UInt64?
        lock.lock()
        if case .checking(let failureCount) = state, let wakeDate, startedAt >= wakeDate {
            if isConnected {
                state = .finished
            } else if failureCount + 1 == 3 {
                state = .finished
                reportGeneration = generation
            } else {
                state = .checking(failureCount: failureCount + 1)
            }
        }
        lock.unlock()

        if let reportGeneration {
            reportQueue.async { [weak self] in
                self?.reportIfCurrent(generation: reportGeneration)
            }
        }
    }

    private func cancelInLock() {
        generation &+= 1
        if case .asleep = state { return }
        state = .finished
    }

    private func reportIfCurrent(generation expectedGeneration: UInt64) {
        lock.lock()
        let isCurrent = generation == expectedGeneration
        lock.unlock()
        guard isCurrent else { return }
        pixelFiring?.fire(VPNWakeConnectivityPixel.failure, frequency: .dailyAndCount, options: .withRetry)
    }
}
