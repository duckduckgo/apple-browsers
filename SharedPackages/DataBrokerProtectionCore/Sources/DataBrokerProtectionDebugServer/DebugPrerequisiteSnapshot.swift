//
//  DebugPrerequisiteSnapshot.swift
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

public struct DebugPrerequisiteResult: Encodable, Sendable {
    public enum Status: String, Encodable, Sendable {
        case pending, ready, unauthenticated, notEntitled, error, bypass, unavailable
    }

    public let status: Status
    public let backend: String
    public let environment: String
    public let pirEnvironment: String?
    public let pirEndpoint: String?
    public let authenticated: Bool?
    public let entitled: Bool?
    public let errorCode: String?

    public init(status: Status, backend: String, environment: String, pirEnvironment: String? = nil,
                pirEndpoint: String? = nil, authenticated: Bool? = nil, errorCode: String? = nil) {
        self.status = status
        self.backend = backend
        self.environment = environment
        self.pirEnvironment = pirEnvironment
        self.pirEndpoint = pirEndpoint
        self.authenticated = authenticated
        self.entitled = status == .ready ? true : status == .notEntitled ? false : nil
        self.errorCode = errorCode
    }
}

/// Owns one generation. The HTTP transport remains synchronous while the normal entitlement reader runs asynchronously.
/// All mutable state is protected by lock; cancellation and generation checks discard late completions.
final class DebugPrerequisiteSnapshot: @unchecked Sendable {
    typealias Reader = @MainActor @Sendable () async throws -> DebugPrerequisiteResult

    struct Snapshot: Encodable {
        let checkID: String
        let instanceID: String?
        let debugRunnerReady: Bool
        let result: DebugPrerequisiteResult
        let checkedAt: Date?
        let errorCode: String?
    }

    private let lock = NSLock()
    private let reader: Reader?
    private let instanceID: String?
    private let debugRunnerReady: Bool
    private let timeout: TimeInterval
    private var current: Snapshot?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var deadline: DispatchWorkItem?
    private var stopped = false

    init(instanceID: String?, timeout: TimeInterval = 30, debugRunnerReady: Bool = false, reader: Reader?) {
        self.instanceID = instanceID
        self.debugRunnerReady = debugRunnerReady
        self.timeout = timeout
        self.reader = reader
    }

    func snapshot(checkID: String) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        if let current, current.checkID == checkID { return current }
        task?.cancel()
        deadline?.cancel()
        guard let reader, !stopped else {
            let snapshot = makeSnapshot(checkID, status: .unavailable)
            current = snapshot
            return snapshot
        }
        let generation = UUID()
        self.generation = generation
        let snapshot = makeSnapshot(checkID, status: .pending)
        current = snapshot
        task = Task { @MainActor [weak self] in
            do {
                let result = try await reader()
                self?.complete(checkID, generation: generation, result: result)
            } catch {
                // Arbitrary error descriptions can contain credentials or service response bodies.
                self?.complete(checkID, generation: generation, result: nil, errorCode: "entitlementCheckFailed")
            }
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.complete(checkID, generation: generation, result: nil, errorCode: "entitlementCheckTimedOut")
        }
        self.deadline = deadline
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        return snapshot
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        current = nil
        task?.cancel()
        task = nil
        deadline?.cancel()
        deadline = nil
    }

    private func complete(_ checkID: String, generation: UUID, result: DebugPrerequisiteResult?, errorCode: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, self.generation == generation, current?.checkID == checkID, current?.result.status == .pending else { return }
        current = Snapshot(checkID: checkID, instanceID: instanceID, debugRunnerReady: debugRunnerReady,
                           result: result ?? DebugPrerequisiteResult(status: .error, backend: "subscription", environment: "unknown"),
                           checkedAt: Date(), errorCode: errorCode)
        task?.cancel()
        task = nil
        deadline?.cancel()
        deadline = nil
    }

    private func makeSnapshot(_ checkID: String, status: DebugPrerequisiteResult.Status) -> Snapshot {
        Snapshot(checkID: checkID, instanceID: instanceID, debugRunnerReady: debugRunnerReady,
                 result: DebugPrerequisiteResult(status: status, backend: "subscription", environment: "unknown"),
                 checkedAt: nil, errorCode: nil)
    }
}
