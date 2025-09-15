//
//  NetworkQualityMonitorMockTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import NetworkQualityMonitor

// MARK: - Mock Tests

final class NetworkQualityMonitorMockTests: XCTestCase {

    func testMockHttpResponseTester() async throws {
        let mockTester = MockHttpResponseTester()
        let result = try await mockTester.performTest(
            configuration: .standard,
            progressCallback: nil
        )

        XCTAssertEqual(result.averageResponseTime, 100)
        XCTAssertEqual(result.responseVariance, 10)
        XCTAssertEqual(result.failureRate, 0)
    }

    func testMockBandwidthTester() async throws {
        let mockTester = MockBandwidthTester()

        let downloadSpeed = try await mockTester.performDownloadTest(
            configuration: .standard,
            progressCallback: nil
        )
        XCTAssertEqual(downloadSpeed, 100)

        let uploadSpeed = try await mockTester.performUploadTest(
            configuration: .standard,
            progressCallback: nil
        )
        XCTAssertEqual(uploadSpeed, 50)
    }

    func testMockDNSTester() async throws {
        let mockTester = MockDNSTester()
        let result = try await mockTester.performTest(
            configuration: .standard,
            progressCallback: nil
        )

        XCTAssertEqual(result.averageResolutionTime, 25)
        XCTAssertEqual(result.failureRate, 0)
    }

    func testMockBufferBloatTester() async throws {
        let mockTester = MockBufferBloatTester()
        let result = try await mockTester.performTest(
            configuration: .standard,
            progressCallback: nil
        )

        XCTAssertEqual(result.baselineLatency, 50)
        XCTAssertEqual(result.loadedLatency, 80)
        XCTAssertEqual(result.increase, 30)
        XCTAssertEqual(result.grade, "A")
    }
}

// MARK: - Mock Implementations

final class MockHttpResponseTester: HttpResponseTesting {
    func performTest(configuration: TestConfiguration,
                     progressCallback: ((String) -> Void)?) async throws -> HttpResponseResult {
        return HttpResponseResult(
            averageResponseTime: 100,
            responseVariance: 10,
            failureRate: 0,
            sampleCount: 15,
            p50: 95,
            p95: 120
        )
    }
}

final class MockBandwidthTester: BandwidthTesting {
    func performDownloadTest(configuration: TestConfiguration,
                             progressCallback: ((String) -> Void)?) async throws -> Double {
        return 100
    }

    func performUploadTest(configuration: TestConfiguration,
                           progressCallback: ((String) -> Void)?) async throws -> Double {
        return 50
    }
}

final class MockDNSTester: DNSTesting {
    func performTest(configuration: TestConfiguration,
                     progressCallback: ((String) -> Void)?) async throws -> DNSResult {
        return DNSResult(averageResolutionTime: 25, failureRate: 0)
    }
}

final class MockBufferBloatTester: BufferBloatTesting {
    func performTest(configuration: TestConfiguration,
                     progressCallback: ((String) -> Void)?) async throws -> BufferBloatResult {
        return BufferBloatResult(
            baselineLatency: 50,
            loadedLatency: 80,
            increase: 30,
            grade: "A"
        )
    }
}

final class MockNetworkSession: NetworkSession {
    var shouldFail = false
    var responseTime: TimeInterval = 0.1

    func data(from url: URL) async throws -> (Data, URLResponse) {
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }

        // Simulate network delay
        try? await Task.sleep(nanoseconds: UInt64(responseTime * 1_000_000_000))

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (Data(repeating: 0, count: 1024), response)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        return try await data(from: url)
    }

    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (Data(), response)
    }
}
