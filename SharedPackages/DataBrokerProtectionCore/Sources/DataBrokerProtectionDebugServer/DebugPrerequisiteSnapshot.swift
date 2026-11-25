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

#if DEBUG
import Foundation
import DataBrokerProtectionCore

public struct DebugPrerequisiteResult: Encodable, Sendable {
    public enum Status: String, Encodable, Sendable {
        case pending, ready, credentialProvided, unauthenticated, notEntitled, error, bypass, unavailable
    }

    public let status: Status
    public let backend: String
    public let environment: String
    public let pirEnvironment: String?
    public let pirEndpoint: String?
    public let authenticated: Bool?
    public let entitled: Bool?
    public let errorCode: String?

    private enum CodingKeys: String, CodingKey {
        case status, backend, environment, pirEnvironment, pirEndpoint, authenticated, entitled, errorCode
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(status, forKey: .status)
        try values.encode(backend, forKey: .backend)
        try values.encode(environment, forKey: .environment)
        try values.encodeIfPresent(pirEnvironment, forKey: .pirEnvironment)
        try values.encodeIfPresent(pirEndpoint, forKey: .pirEndpoint)
        try values.encodeIfPresent(authenticated, forKey: .authenticated)
        try values.encode(entitled, forKey: .entitled)
        try values.encodeIfPresent(errorCode, forKey: .errorCode)
    }

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

    @MainActor
    public static func subscription(_ manager: DataBrokerProtectionSubscriptionManager,
                                    settings: DataBrokerProtectionSettings) async -> DebugPrerequisiteResult {
        let settings = settings.isolatedDebugSettingsForLaunch()
        let status: Status
        let backend: String
        let environment: String
        let authenticated: Bool
        var errorCode: String?
        if manager.isDebugAccessTokenProvided {
            authenticated = manager.isDebugAccessTokenValid
            status = authenticated ? .credentialProvided : .error
            backend = "provided-token"
            environment = settings.selectedEnvironment.rawValue
            errorCode = authenticated ? nil : "invalidProvidedCredential"
        } else if manager.isEntitlementCheckBypassed {
            return DebugPrerequisiteResult(status: .bypass, backend: "subscription", environment: "integrationTests")
        } else {
            authenticated = manager.isSubscriptionAuthenticated
            backend = "subscription-auth-v2"
            environment = manager.entitlementEnvironment
            if !authenticated {
                status = .unauthenticated
            } else {
                do {
                    status = try await manager.debugEntitlement() ? .ready : .notEntitled
                } catch {
                    status = .error
                    errorCode = "entitlementCheckFailed"
                }
            }
        }
        var endpoint = URLComponents(url: settings.endpointURL, resolvingAgainstBaseURL: false)
        endpoint?.user = nil
        endpoint?.password = nil
        endpoint?.query = nil
        endpoint?.fragment = nil
        return DebugPrerequisiteResult(status: status, backend: backend, environment: environment,
                                       pirEnvironment: settings.selectedEnvironment.rawValue, pirEndpoint: endpoint?.string,
                                       authenticated: authenticated, errorCode: errorCode)
    }
}

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
#endif
