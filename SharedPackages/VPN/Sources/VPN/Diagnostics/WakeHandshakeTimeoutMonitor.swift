//
//  WakeHandshakeTimeoutMonitor.swift
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
import Network
import PixelKit

/// Records repeated native WireGuard timeouts after wake, without querying or changing the tunnel.
/// An authenticated incoming handshake ends this observation; it does not prove session completion.
public final class WakeHandshakeTimeoutMonitor: @unchecked Sendable {
    private enum State {
        case asleep
        case waitingForRequest
        case waitingForTimeouts(peer: String, count: Int)
        case finished
    }

    private struct PathIdentity: Equatable {
        let isSatisfied: Bool
        let interfaces: [String]
    }

    private let lock = NSLock()
    private var state: State = .asleep
    private var generation: UInt64 = 0
    private var previousPath: PathIdentity?
    private let pathMonitor: NWPathMonitor?
    private let reportQueue: DispatchQueue
    private let pixelFiring: PixelKitFiring?

    public convenience init(pixelFiring: PixelKitFiring? = PixelKit.shared) {
        self.init(pixelFiring: pixelFiring, pathMonitor: NWPathMonitor(),
                  reportQueue: DispatchQueue(label: "com.duckduckgo.vpn.wake-handshake-pixel"))
    }

    init(pixelFiring: PixelKitFiring?, pathMonitor: NWPathMonitor?, reportQueue: DispatchQueue) {
        self.pixelFiring = pixelFiring
        self.pathMonitor = pathMonitor
        self.reportQueue = reportQueue
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            let interfaces = path.availableInterfaces.filter {
                [.wifi, .cellular, .wiredEthernet].contains($0.type) && path.usesInterfaceType($0.type)
            }.map { "\($0.type):\($0.name):\($0.index)" }
            self?.updatePath(isSatisfied: path.status == .satisfied, physicalInterfaces: interfaces)
        }
        pathMonitor?.start(queue: DispatchQueue(label: "com.duckduckgo.vpn.wake-handshake-path"))
    }

    deinit {
        pathMonitor?.cancel()
    }

    public func wake(isEligible: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard isEligible, previousPath?.isSatisfied != false else {
            cancelInLock()
            state = .finished
            return
        }
        // Duplicate wake notifications must not restart an ended or partially counted cycle.
        guard case .asleep = state else { return }
        state = .waitingForRequest
    }

    public func sleep() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        state = .asleep
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelInLock()
    }

    /// Called directly from the native logger. No runtime reads, network requests or pixel sends here.
    public func consumeLog(_ message: String) {
        guard message.hasPrefix("peer("), let separator = message.range(of: ") - ") else { return }
        let peer = String(message[..<separator.lowerBound])
        let detail = String(message[separator.upperBound...])
        let isProgress = detail == "Received handshake response" || detail == "Received handshake initiation"
        let isTimeout = detail.range(of: #"^Handshake did not complete after [0-9]+ seconds, retrying \(try [0-9]+\)$"#,
                                     options: .regularExpression) != nil
        var reportGeneration: UInt64?

        lock.lock()
        switch state {
        case .waitingForRequest:
            if isProgress {
                state = .finished
            } else if detail == "Sending handshake initiation" {
                state = .waitingForTimeouts(peer: peer, count: 0)
            }
        case .waitingForTimeouts(let expectedPeer, let count) where expectedPeer == peer:
            if isProgress {
                state = .finished
            } else if isTimeout {
                if count + 1 == 2 {
                    state = .finished
                    reportGeneration = generation
                } else {
                    state = .waitingForTimeouts(peer: peer, count: count + 1)
                }
            }
        default: break
        }
        lock.unlock()

        if let reportGeneration {
            reportQueue.async { [weak self] in
                self?.reportIfCurrent(generation: reportGeneration)
            }
        }
    }

    func updatePath(isSatisfied: Bool, physicalInterfaces: [String]) {
        let path = PathIdentity(isSatisfied: isSatisfied, interfaces: physicalInterfaces.sorted())
        lock.lock()
        defer { lock.unlock() }
        // Initial delivery seeds the identity. Quality/DNS updates and equivalent paths do not cancel.
        if !isSatisfied || previousPath.map({ $0 != path }) == true {
            cancelInLock()
        }
        previousPath = path
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
        pixelFiring?.fire(VPNWakeHandshakePixel.timeouts, frequency: .dailyAndCount, options: .withRetry)
    }
}
