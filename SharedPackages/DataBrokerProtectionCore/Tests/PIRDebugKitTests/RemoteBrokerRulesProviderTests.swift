//
//  RemoteBrokerRulesProviderTests.swift
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
import ZIPFoundation
@testable import PIRDebugKit

/// A `URLProtocol` that serves canned responses. Never hits the network.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let data: Data
        let headers: [String: String]
    }

    /// Handler keyed off the request; returns the stub to serve.
    static var handler: ((URLRequest) -> Stub)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let stub = handler(request)
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: stub.statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RemoteBrokerRulesProviderTests: XCTestCase {

    private var session: URLSession!
    private var tempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        session = nil
        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        tempFiles = []
        super.tearDown()
    }

    private func validBrokerData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "fakebroker.com", withExtension: "json", subdirectory: "Resources"))
        return try Data(contentsOf: url)
    }

    /// Builds an `all.zip` containing `json/fakebroker.com.json` and `json/notactive.com.json`.
    private func makeAllBrokersZip() throws -> Data {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let jsonDir = workDir.appendingPathComponent("json", isDirectory: true)
        try fm.createDirectory(at: jsonDir, withIntermediateDirectories: true)
        tempFiles.append(workDir)

        let brokerData = try validBrokerData()
        try brokerData.write(to: jsonDir.appendingPathComponent("fakebroker.com.json"))

        let otherString = String(data: brokerData, encoding: .utf8)!.replacingOccurrences(of: "fakebroker.com", with: "notactive.com")
        try Data(otherString.utf8).write(to: jsonDir.appendingPathComponent("notactive.com.json"))

        let zipURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("zip")
        tempFiles.append(zipURL)
        try fm.zipItem(at: jsonDir, to: zipURL, shouldKeepParent: true)
        return try Data(contentsOf: zipURL)
    }

    private func mainConfigJSON(active: [String], test: [String]) -> Data {
        let dict: [String: Any] = [
            "main_config_etag": "etag-123",
            "active_data_brokers": active,
            "test_data_brokers": test,
            "json_etags": ["current": [:]]
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    func testFetchBrokersReturnsOnlyActiveBrokers() async throws {
        let zipData = try makeAllBrokersZip()
        let configData = mainConfigJSON(active: ["fakebroker.com.json"], test: ["notactive.com.json"])

        StubURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            if url.contains("main_config.json") {
                return .init(statusCode: 200, data: configData, headers: ["Etag": "etag-123"])
            } else {
                return .init(statusCode: 200, data: zipData, headers: [:])
            }
        }

        let provider = RemoteBrokerRulesProvider(endpoint: .staging, urlSession: session)
        let brokers = try await provider.fetchBrokers()

        XCTAssertEqual(brokers.count, 1, "Only active brokers should be decoded")
        XCTAssertEqual(brokers.first?.url, "fakebroker.com")
    }

    func testFetchBrokersIncludesTestBrokersWhenEnabled() async throws {
        let zipData = try makeAllBrokersZip()
        let configData = mainConfigJSON(active: ["fakebroker.com.json"], test: ["notactive.com.json"])

        StubURLProtocol.handler = { request in
            let url = request.url!.absoluteString
            if url.contains("main_config.json") {
                return .init(statusCode: 200, data: configData, headers: [:])
            } else {
                return .init(statusCode: 200, data: zipData, headers: [:])
            }
        }

        let provider = RemoteBrokerRulesProvider(endpoint: .staging, includeTestBrokers: true, urlSession: session)
        let brokers = try await provider.fetchBrokers()

        XCTAssertEqual(brokers.count, 2)
        XCTAssertEqual(Set(brokers.map(\.url)), ["fakebroker.com", "notactive.com"])
    }

    func testMainConfigNotModifiedThrows() async throws {
        StubURLProtocol.handler = { request in
            // The provider only sends If-None-Match on the main_config request.
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "etag-123")
            return .init(statusCode: 304, data: Data(), headers: [:])
        }

        let provider = RemoteBrokerRulesProvider(endpoint: .staging, eTag: "etag-123", urlSession: session)
        do {
            _ = try await provider.fetchBrokers()
            XCTFail("Expected remoteRulesNotModified")
        } catch PIRDebugError.remoteRulesNotModified {
            // expected
        }
    }

    func testMainConfigServerErrorThrows() async {
        StubURLProtocol.handler = { _ in .init(statusCode: 500, data: Data(), headers: [:]) }

        let provider = RemoteBrokerRulesProvider(endpoint: .staging, urlSession: session)
        do {
            _ = try await provider.fetchBrokers()
            XCTFail("Expected remoteRulesServerError")
        } catch PIRDebugError.remoteRulesServerError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEndpointRequestsUseUnauthenticatedPaths() async throws {
        let zipData = try makeAllBrokersZip()
        let configData = mainConfigJSON(active: ["fakebroker.com.json"], test: [])
        var sawAuthHeader = false
        var mainConfigPath: String?

        StubURLProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "Authorization") != nil { sawAuthHeader = true }
            let url = request.url!.absoluteString
            if url.contains("main_config.json") {
                mainConfigPath = request.url!.path
                return .init(statusCode: 200, data: configData, headers: [:])
            }
            return .init(statusCode: 200, data: zipData, headers: [:])
        }

        let provider = RemoteBrokerRulesProvider(endpoint: .stagingBranch("randerson/fix-foo"), urlSession: session)
        _ = try await provider.fetchBrokers()

        XCTAssertFalse(sawAuthHeader, "Remote rules endpoints must be requested without an Authorization header")
        XCTAssertEqual(mainConfigPath, "/branches/randerson-fix-foo/dbp/remote/v0/main_config.json")
    }
}
