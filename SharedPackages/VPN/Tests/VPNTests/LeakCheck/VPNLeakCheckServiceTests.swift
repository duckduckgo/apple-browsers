//
//  VPNLeakCheckServiceTests.swift
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
import PixelKit
@testable import VPN

final class VPNLeakCheckServiceTests: XCTestCase {

    func testAllProbesMatchEgress_allSuccess() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressIP: "1.2.3.4",
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent,
            contextName: "Test-Context"
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try! XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .success)
        XCTAssertEqual(data.ipv4Https?.status, .success)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
        XCTAssertEqual(data.ipv6Http?.status, .success)
        XCTAssertEqual(data.ipv6Https?.status, .success)
        XCTAssertEqual(data.ipv6Stun?.status, .success)
        XCTAssertNil(data.ipv4LeakIPType)
    }

    func testIPv4Mismatch_detectsLeakAndClassifiesType() async {
        let http = MockLeakCheckHTTPClient(ipv4: "8.8.8.8", ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressIP: "1.2.3.4",
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent,
            contextName: "Test-Context"
        )

        await service.runCheck(trigger: .periodic)

        let data = try! XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .leak)
        XCTAssertEqual(data.ipv4Https?.status, .leak)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
        XCTAssertEqual(data.ipv4LeakIPType, .public)
    }

    func testIPv6Response_detectsLeak() async {
        let http = MockLeakCheckHTTPClient(ipv4: "1.2.3.4", ipv6: "2001:db8::1")
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressIP: "1.2.3.4",
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent,
            contextName: "Test-Context"
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try! XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv6Http?.status, .leak)
        XCTAssertEqual(data.ipv6Https?.status, .leak)
        XCTAssertEqual(data.ipv6Stun?.status, .success)
        XCTAssertEqual(data.ipv6LeakIPType, .public)
    }

    func testIPv6ConnectionError_mapsToSuccess() async {
        let http = MockLeakCheckHTTPClient(
            ipv4: "1.2.3.4",
            ipv6Error: URLError(.cannotFindHost)
        )
        let stun = MockLeakCheckSTUNClient(
            ipv4: "1.2.3.4",
            ipv6Error: URLError(.cannotFindHost)
        )
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressIP: "1.2.3.4",
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent,
            contextName: "Test-Context"
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try! XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv6Http?.status, .success)
        XCTAssertEqual(data.ipv6Https?.status, .success)
        XCTAssertEqual(data.ipv6Stun?.status, .success)
    }

    func testIPv4ProbeError_recordedAsError() async {
        let http = MockLeakCheckHTTPClient(ipv4Error: URLError(.timedOut), ipv6Error: URLError(.cannotFindHost))
        let stun = MockLeakCheckSTUNClient(ipv4: "1.2.3.4", ipv6Error: URLError(.cannotFindHost))
        let wideEvent = MockWideEventManager()
        let service = VPNLeakCheckService(
            configuration: .default,
            egressIP: "1.2.3.4",
            httpClient: http,
            stunClient: stun,
            wideEvent: wideEvent,
            contextName: "Test-Context"
        )

        await service.runCheck(trigger: .tunnelStart)

        let data = try! XCTUnwrap(wideEvent.lastCompletedData)
        XCTAssertEqual(data.ipv4Http?.status, .error)
        XCTAssertEqual(data.ipv4Http?.errorDomain, URLError.errorDomain)
        XCTAssertEqual(data.ipv4Http?.errorCode, URLError.timedOut.rawValue)
        XCTAssertEqual(data.ipv4Stun?.status, .success)
    }
}

// MARK: - Mocks

final class MockLeakCheckHTTPClient: LeakCheckHTTPClient, @unchecked Sendable {
    var ipv4: String?
    var ipv6: String?
    var ipv4Error: Error?
    var ipv6Error: Error?

    init(ipv4: String? = nil, ipv6: String? = nil, ipv4Error: Error? = nil, ipv6Error: Error? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.ipv4Error = ipv4Error
        self.ipv6Error = ipv6Error
    }

    func fetchIP(
        host: String,
        port: UInt16,
        scheme: LeakCheckScheme,
        ipVersion: IPVersion,
        timeout: TimeInterval
    ) async throws -> String {
        switch ipVersion {
        case .v4:
            if let error = ipv4Error { throw error }
            return ipv4 ?? ""
        case .v6:
            if let error = ipv6Error { throw error }
            return ipv6 ?? ""
        }
    }
}

final class MockLeakCheckSTUNClient: LeakCheckSTUNClient, @unchecked Sendable {
    var ipv4: String?
    var ipv6: String?
    var ipv4Error: Error?
    var ipv6Error: Error?

    init(ipv4: String? = nil, ipv6: String? = nil, ipv4Error: Error? = nil, ipv6Error: Error? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.ipv4Error = ipv4Error
        self.ipv6Error = ipv6Error
    }

    func sendBindingRequest(
        host: String,
        port: UInt16,
        ipVersion: IPVersion,
        timeout: TimeInterval
    ) async throws -> String {
        switch ipVersion {
        case .v4:
            if let error = ipv4Error { throw error }
            return ipv4 ?? ""
        case .v6:
            if let error = ipv6Error { throw error }
            return ipv6 ?? ""
        }
    }
}

final class MockWideEventManager: WideEventManaging, @unchecked Sendable {
    var startedFlows: [Any] = []
    var lastCompletedData: VPNIPLeakCheckWideEventData?
    var lastCompletedStatus: WideEventStatus?
    var discardedCount = 0

    func startFlow<T: WideEventData>(_ data: T) {
        startedFlows.append(data)
    }
    func updateFlow<T: WideEventData>(_ data: T) {}
    func updateFlow<T: WideEventData>(globalID: String, update: (inout T) -> Void) {}
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus, onComplete: @escaping PixelKit.CompletionBlock) {
        if let data = data as? VPNIPLeakCheckWideEventData {
            lastCompletedData = data
            lastCompletedStatus = status
        }
        onComplete(true, nil)
    }
    func completeFlow<T: WideEventData>(_ data: T, status: WideEventStatus) async throws -> Bool {
        if let data = data as? VPNIPLeakCheckWideEventData {
            lastCompletedData = data
            lastCompletedStatus = status
        }
        return true
    }
    func discardFlow<T: WideEventData>(_ data: T) {
        discardedCount += 1
    }
    func getFlowData<T: WideEventData>(_ type: T.Type, globalID: String) -> T? { nil }
    func getAllFlowData<T: WideEventData>(_ type: T.Type) -> [T] { [] }
}
