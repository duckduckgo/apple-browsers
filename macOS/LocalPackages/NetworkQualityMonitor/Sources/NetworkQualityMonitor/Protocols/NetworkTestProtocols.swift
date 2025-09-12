//
//  NetworkTestProtocols.swift
//  NetworkQualityMonitor
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

import Foundation

// MARK: - Core Protocol

/// Main protocol for network quality monitoring
public protocol NetworkQualityMonitoring {
    func runTest() async throws -> NetworkTestResults
    func checkConnectivity() async -> Bool
}

// MARK: - Test Component Protocols

/// Protocol for HTTP response testing
public protocol HttpResponseTesting {
    func performTest(configuration: TestConfiguration, 
                     progressCallback: ((String) -> Void)?) async throws -> HttpResponseResult
}

/// Protocol for bandwidth testing
public protocol BandwidthTesting {
    func performDownloadTest(configuration: TestConfiguration,
                            progressCallback: ((String) -> Void)?) async throws -> Double
    func performUploadTest(configuration: TestConfiguration,
                          progressCallback: ((String) -> Void)?) async throws -> Double
}

/// Protocol for DNS testing
public protocol DNSTesting {
    func performTest(configuration: TestConfiguration,
                    progressCallback: ((String) -> Void)?) async throws -> DNSResult
}

/// Protocol for buffer bloat testing
public protocol BufferBloatTesting {
    func performTest(configuration: TestConfiguration,
                    progressCallback: ((String) -> Void)?) async throws -> BufferBloatResult
}

// MARK: - Scoring Protocol

/// Protocol for score calculation
public protocol NetworkScoreCalculating {
    func calculateOverallScore(httpResponse: HttpResponseResult,
                              bandwidth: BandwidthResult,
                              dns: DNSResult,
                              bufferBloat: BufferBloatResult) -> NetworkScore
    
    func determineQuality(from score: Double) -> NetworkQuality
}

// MARK: - Progress Reporting

/// Protocol for progress reporting
public protocol NetworkTestProgressReporting: AnyObject {
    var progressCallback: ((Double, String) -> Void)? { get set }
}

// MARK: - Network Session Protocol

/// Protocol for network operations (mockable for testing)
public protocol NetworkSession {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse)
}

// Extension to make URLSession conform to our protocol
extension URLSession: NetworkSession {
}