//
//  DebugMaintenanceOperations.swift
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

#if DEBUG
import DataBrokerProtectionCore
import Foundation

/// A broker as stored after a debug broker JSON refresh.
public struct DebugBrokerState: Codable, Equatable, Sendable {
    public let url: String
    public let version: String
    public let isRemoved: Bool
    public let id: Int64?

    public init(url: String, version: String, isRemoved: Bool, id: Int64?) {
        self.url = url
        self.version = version
        self.isRemoved = isRemoved
        self.id = id
    }

    public init(_ broker: DataBroker) {
        self.init(url: broker.url, version: broker.version, isRemoved: broker.removedAt != nil, id: broker.id)
    }
}

/// The scans a debug immediate-scan request queued, and the requested brokers it couldn't queue.
public struct DebugImmediateScans: Codable, Equatable, Sendable {
    public let queued: [PIRDebugLaunchOptions.DebugScanJob]
    public let notQueued: [String]

    public init(queued: [PIRDebugLaunchOptions.DebugScanJob], requested: [String]) {
        self.queued = queued
        let planned = Set(queued.map(\.brokerURL))
        self.notQueued = requested.filter { !planned.contains($0) }
    }
}

/// Runs debug maintenance work off the synchronous HTTP handler; callers poll an operation by its ID.
final class DebugMaintenanceOperations: @unchecked Sendable {
    struct State: Encodable {
        let id: String
        let kind: String
        let status: String
        let result: AnyEncodable?
        let error: String?
    }

    private let lock = NSLock()
    private var states: [String: State] = [:]

    func start<Result: Encodable & Sendable>(kind: String, _ work: @escaping @MainActor @Sendable () async throws -> Result) -> State {
        let id = UUID().uuidString
        let pending = State(id: id, kind: kind, status: "pending", result: nil, error: nil)
        lock.withLock { states[id] = pending }
        Task { @MainActor [weak self] in
            let state: State
            do {
                state = State(id: id, kind: kind, status: "succeeded", result: AnyEncodable(try await work()), error: nil)
            } catch {
                state = State(id: id, kind: kind, status: "failed", result: nil, error: String(describing: error))
            }
            self?.lock.withLock { self?.states[id] = state }
        }
        return pending
    }

    func state(id: String) -> State? {
        lock.withLock { states[id] }
    }
}

struct AnyEncodable: Encodable, @unchecked Sendable {
    private let encodeValue: (Encoder) throws -> Void

    init<Value: Encodable>(_ value: Value) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
#endif
