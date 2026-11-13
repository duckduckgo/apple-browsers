//
//  DebugPrerequisiteSnapshotTests.swift
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

import XCTest
import DebugServer
@testable import DataBrokerProtectionDebugServer

final class DebugPrerequisiteSnapshotTests: XCTestCase {

    func testMissingReaderIsUnavailable() {
        let owner = DebugPrerequisiteSnapshot(instanceID: "owner", reader: nil)
        let snapshot = owner.snapshot(checkID: "first")
        XCTAssertEqual(snapshot.instanceID, "owner")
        XCTAssertEqual(snapshot.result.status, .unavailable)
        XCTAssertNil(snapshot.checkedAt)
    }

    @MainActor
    func testReadyFalseAndBypassRemainDistinct() async throws {
        for status in [DebugPrerequisiteResult.Status.ready, .notEntitled, .bypass] {
            let owner = DebugPrerequisiteSnapshot(instanceID: "owner") {
                DebugPrerequisiteResult(status: status, backend: "subscription", environment: "staging")
            }
            XCTAssertEqual(owner.snapshot(checkID: "first").result.status, .pending)
            let result = try await completed(owner, id: "first")
            XCTAssertEqual(result.result.status, status)
            XCTAssertNotNil(result.checkedAt)
            owner.stop()
        }
    }

    @MainActor
    func testErrorResponseDoesNotSerializeCredentials() async throws {
        struct SecretError: LocalizedError {
            var errorDescription: String? { "Bearer secret-token" }
        }
        let owner = DebugPrerequisiteSnapshot(instanceID: "owner") { throw SecretError() }
        _ = owner.snapshot(checkID: "first")
        let result = try await completed(owner, id: "first")
        XCTAssertEqual(result.result.status, .error)
        XCTAssertEqual(result.errorCode, "entitlementCheckFailed")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(result), encoding: .utf8))
        XCTAssertFalse(json.contains("secret-token"))
        owner.stop()
    }

    @MainActor
    func testSameIDPollsOneCheckAndNewIDRejectsLateCompletion() async throws {
        let gate = Gate()
        let owner = DebugPrerequisiteSnapshot(instanceID: "owner", reader: { await gate.read() })
        _ = owner.snapshot(checkID: "first")
        _ = owner.snapshot(checkID: "first")
        try await gate.waitForCount(1)
        XCTAssertEqual(gate.continuations.count, 1)
        _ = owner.snapshot(checkID: "second")
        try await gate.waitForCount(2)
        gate.resume(0, status: .ready)
        await Task.yield()
        XCTAssertEqual(owner.snapshot(checkID: "second").result.status, .pending)
        gate.resume(1, status: .notEntitled)
        let result = try await completed(owner, id: "second")
        XCTAssertEqual(result.result.status, .notEntitled)
        owner.stop()
    }

    @MainActor
    func testReusedIDStillRejectsEarlierGeneration() async throws {
        let gate = Gate()
        let owner = DebugPrerequisiteSnapshot(instanceID: "owner", reader: { await gate.read() })
        _ = owner.snapshot(checkID: "first")
        try await gate.waitForCount(1)
        _ = owner.snapshot(checkID: "second")
        try await gate.waitForCount(2)
        _ = owner.snapshot(checkID: "first")
        try await gate.waitForCount(3)
        gate.resume(0, status: .ready)
        gate.resume(1, status: .ready)
        await Task.yield()
        XCTAssertEqual(owner.snapshot(checkID: "first").result.status, .pending)
        gate.resume(2, status: .bypass)
        let result = try await completed(owner, id: "first")
        XCTAssertEqual(result.result.status, .bypass)
        owner.stop()
    }

    @MainActor
    func testTimeoutIsTerminalEvenWhenReaderCompletesLate() async throws {
        let gate = Gate()
        let owner = DebugPrerequisiteSnapshot(instanceID: "owner", timeout: 0.02, reader: { await gate.read() })
        _ = owner.snapshot(checkID: "first")
        try await gate.waitForCount(1)
        let result = try await completed(owner, id: "first")
        XCTAssertEqual(result.errorCode, "entitlementCheckTimedOut")
        gate.resume(0, status: .ready)
        await Task.yield()
        XCTAssertEqual(owner.snapshot(checkID: "first").result.status, .error)
        owner.stop()
    }

    @MainActor
    func testStopRejectsLateCompletionAndFurtherChecks() async throws {
        let gate = Gate()
        let owner = DebugPrerequisiteSnapshot(instanceID: "owner", reader: { await gate.read() })
        _ = owner.snapshot(checkID: "first")
        try await gate.waitForCount(1)
        owner.stop()
        gate.resume(0, status: .ready)
        await Task.yield()
        XCTAssertEqual(owner.snapshot(checkID: "first").result.status, .unavailable)
    }

    func testMutationOwnershipRequiresExactHeader() {
        let request = HTTPRequest(method: .POST, path: "/api/debug/scans", headers: ["x-pir-debug-instance": "owner"])
        XCTAssertTrue(DataBrokerProtectionDebugHTTPServer.isOwned(request, instanceID: "owner"))
        XCTAssertFalse(DataBrokerProtectionDebugHTTPServer.isOwned(request, instanceID: "other"))
        let missing = HTTPRequest(method: .POST, path: "/api/debug/scans")
        XCTAssertFalse(DataBrokerProtectionDebugHTTPServer.isOwned(missing, instanceID: "owner"))
        XCTAssertTrue(DataBrokerProtectionDebugHTTPServer.isOwned(missing, instanceID: nil))
    }

    @MainActor
    private func completed(_ owner: DebugPrerequisiteSnapshot, id: String) async throws -> DebugPrerequisiteSnapshot.Snapshot {
        for _ in 0..<1_000 {
            let snapshot = owner.snapshot(checkID: id)
            if snapshot.result.status != .pending { return snapshot }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw NSError(domain: "test prerequisite timeout", code: 1)
    }
}

@MainActor
private final class Gate {
    var continuations: [CheckedContinuation<DebugPrerequisiteResult, Never>] = []

    func read() async -> DebugPrerequisiteResult {
        await withCheckedContinuation { continuations.append($0) }
    }

    func resume(_ index: Int, status: DebugPrerequisiteResult.Status) {
        continuations[index].resume(returning: DebugPrerequisiteResult(status: status, backend: "subscription", environment: "staging"))
    }

    func waitForCount(_ count: Int) async throws {
        for _ in 0..<1_000 {
            if continuations.count >= count { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw NSError(domain: "test reader did not start", code: 1)
    }
}
