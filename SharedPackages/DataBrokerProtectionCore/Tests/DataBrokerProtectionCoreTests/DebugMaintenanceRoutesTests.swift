//
//  DebugMaintenanceRoutesTests.swift
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

#if os(macOS) && DEBUG
import Darwin
import Foundation
import XCTest
import DataBrokerProtectionCore
import DataBrokerProtectionDebugServer

final class DebugMaintenanceRoutesTests: XCTestCase {
    private let instance = UUID().uuidString
    private var port: UInt16 = 0

    func testRefreshAndImmediateScansRunAsPolledOperationsAndRejectWebPages() async throws {
        port = try availablePort()
        let calls = Calls()
        let server = DataBrokerProtectionDebugHTTPServer(provider: EmptyProvider(), port: port, instanceID: instance)
        server.brokerJSONRefresher = { resetDelivery in
            calls.append("refresh:\(resetDelivery)")
            return [DebugBrokerState(url: "beenverified.com", version: "0.12.0", isRemoved: false, id: 7)]
        }
        server.immediateScanStarter = { brokers in
            calls.append("scan:\(brokers.joined(separator: ","))")
            return DebugImmediateScans(queued: [.init(brokerURL: "searchpeoplefree.com", profileQueryId: 1)], requested: brokers)
        }
        try server.start()
        defer { server.stop() }

        let refreshStarted = try await post("/api/debug/broker-json/refresh", body: #"{"resetDelivery":true}"#)
        let refresh = try await operation(refreshStarted)
        XCTAssertEqual(refresh["status"] as? String, "succeeded")
        XCTAssertEqual((refresh["result"] as? [[String: Any]])?.first?["version"] as? String, "0.12.0")

        let scansStarted = try await post("/api/debug/scans/immediate", body: #"{"brokers":["searchpeoplefree.com","beenverified.com"]}"#)
        let scans = try await operation(scansStarted)
        let result = try XCTUnwrap(scans["result"] as? [String: Any])
        XCTAssertEqual((result["queued"] as? [[String: Any]])?.map { $0["brokerURL"] as? String }, ["searchpeoplefree.com"])
        XCTAssertEqual(result["notQueued"] as? [String], ["beenverified.com"])
        XCTAssertEqual(calls.values, ["refresh:true", "scan:searchpeoplefree.com,beenverified.com"])

        let emptyBrokers = try await post("/api/debug/scans/immediate", body: #"{"brokers":[]}"#)
        XCTAssertEqual(emptyBrokers.status, 400)
        let fromWebPage = try await post("/api/debug/broker-json/refresh", body: "{}", origin: "https://example.com")
        XCTAssertEqual(fromWebPage.status, 403)
        let otherInstance = try await post("/api/debug/broker-json/refresh", body: "{}", instance: "other")
        XCTAssertEqual(otherInstance.status, 403)
        XCTAssertEqual(calls.values.count, 2)
    }

    private func post(_ path: String, body: String, origin: String? = nil, instance: String? = nil) async throws -> (status: Int, json: Any?) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue(instance ?? self.instance, forHTTPHeaderField: "X-PIR-Debug-Instance")
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (status: Int, json: Any?) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: data))
    }

    private func operation(_ started: (status: Int, json: Any?)) async throws -> [String: Any] {
        XCTAssertEqual(started.status, 202)
        let id = try XCTUnwrap((started.json as? [String: Any])?["id"] as? String)
        for _ in 0..<50 {
            let polled = try await send(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/debug/maintenance/\(id)")!))
            let state = try XCTUnwrap(polled.json as? [String: Any])
            if state["status"] as? String != "pending" { return state }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("maintenance operation \(id) stayed pending")
        return [:]
    }

    private func availablePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
        }
        guard read == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return UInt16(bigEndian: address.sin_port)
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    var values: [String] { lock.withLock { calls } }
    func append(_ call: String) { lock.withLock { calls.append(call) } }
}

private final class EmptyProvider: DataBrokerProtectionDebugReadProviding {
    let agentVersion = "maintenance-test"
    let schedulerStateString = "stub"
    let lastSchedulerTrigger: Date? = nil
    let environmentName = "staging"
    let endpointURL = URL(string: "https://dbp-staging.duckduckgo.com")!
    let mainConfigETag: String? = nil
    let lastBrokerJSONUpdateCheck = Date.distantPast
    func brokerProfileQueryData() throws -> [BrokerProfileQueryData] { [] }
}
#endif
