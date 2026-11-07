//
//  NativeWireGuardTransport.swift
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

#if DEBUG && (os(macOS) || os(iOS))
import Foundation
import Network
import VPN

protocol NativeWireGuardTransport: AnyObject {
    func start(queue: DispatchQueue, stateChanged: @escaping (NWConnection.State) -> Void)
    func send(_ datagram: Data, completion: @escaping (NWError?) -> Void)
    func batch(_ sends: () -> Void)
    func receive(completion: @escaping ([Data], NWError?) -> Void)
    func cancel()
}

extension NativeWireGuardTransport {
    func batch(_ sends: () -> Void) { sends() }
}

final class UDPWireGuardTransport: NativeWireGuardTransport {
    private let connection: NWConnection
    private let queueKey = DispatchSpecificKey<Bool>()
    private var callbackQueue: DispatchQueue?
    private var receiveCompletion: (([Data], NWError?) -> Void)?
    private var receivedDatagrams: [Data] = []
    private var outstandingReceives = 0
    private var completedReceive = false
    private var receiveError: NWError?
    private var receiveFlushScheduled = false
    private var cancelled = false
    // Bound completed datagrams plus outstanding receives together, including between batches.
    private static let receiveWindow = 32
    private static let maximumDatagramBytes = 65_535

    init(endpoint: Endpoint) {
        // Ordinary provider-created connections use the direct path. The outer WireGuard
        // connection must never set requiredInterface to the provider's virtual interface.
        connection = NWConnection(host: endpoint.host, port: endpoint.port, using: .udp)
    }

    func start(queue: DispatchQueue, stateChanged: @escaping (NWConnection.State) -> Void) {
        callbackQueue = queue
        queue.setSpecific(key: queueKey, value: true)
        connection.stateUpdateHandler = stateChanged
        connection.start(queue: queue)
    }

    func batch(_ sends: () -> Void) {
        connection.batch(sends)
    }

    func send(_ datagram: Data, completion: @escaping (NWError?) -> Void) {
        connection.send(content: datagram, completion: .contentProcessed(completion))
    }

    func receive(completion: @escaping ([Data], NWError?) -> Void) {
        guard !cancelled else { return }
        precondition(receiveCompletion == nil, "Only one receive-batch consumer may be registered")
        receiveCompletion = completion
        scheduleReceiveFlush()
        guard receiveError == nil else { return }
        let count = Self.receiveWindow - outstandingReceives - receivedDatagrams.count
        guard count > 0 else { return }
        outstandingReceives += count
        connection.batch {
            for _ in 0..<count {
                connection.receiveMessage { [weak self] data, _, _, error in
                    guard let self, !self.cancelled else { return }
                    self.outstandingReceives -= 1
                    self.completedReceive = true
                    if let data, data.count <= Self.maximumDatagramBytes {
                        self.receivedDatagrams.append(data)
                    }
                    if let error { self.receiveError = error }
                    self.scheduleReceiveFlush()
                }
            }
        }
    }

    private func scheduleReceiveFlush() {
        guard completedReceive, receiveCompletion != nil, !receiveFlushScheduled, let callbackQueue else { return }
        receiveFlushScheduled = true
        // Coalesce callbacks already ready on this queue; a single packet never waits for a full batch.
        callbackQueue.async { [weak self] in
            guard let self, !self.cancelled else { return }
            self.receiveFlushScheduled = false
            guard let completion = self.receiveCompletion else { return }
            self.receiveCompletion = nil
            let datagrams = self.receivedDatagrams
            self.receivedDatagrams = []
            self.completedReceive = false
            completion(datagrams, self.receiveError)
        }
    }

    func cancel() {
        connection.cancel()
        if DispatchQueue.getSpecific(key: queueKey) == true {
            cancelReceives()
        } else {
            callbackQueue?.async { [weak self] in self?.cancelReceives() }
        }
    }

    private func cancelReceives() {
        cancelled = true
        receiveCompletion = nil
        receivedDatagrams.removeAll()
        outstandingReceives = 0
        completedReceive = false
        receiveFlushScheduled = false
    }
}
#endif
