//
//  StubURLProtocol.swift
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
import Testing

/// Parent of every suite that uses `StubURLProtocol`: its state is static, so those suites must not run in parallel.
@Suite(.serialized)
struct StubbedNetworkTests {}

/// Serves canned responses to sessions built with `StubURLProtocol.configuration()`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Every request the stub received. Appended on URLSession's thread while tests read it, so it's locked.
    static var requests: [URLRequest] { lock.withLock { recordedRequests } }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []
    /// Seconds to wait before answering, so tests can act while a download is in flight.
    nonisolated(unsafe) static var delay: TimeInterval = 0

    static func reset() {
        handler = nil
        lock.withLock { recordedRequests = [] }
        delay = 0
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.recordedRequests.append(request) }
        let result = Result { () throws -> (HTTPURLResponse, Data) in
            guard let handler = Self.handler else { throw URLError(.unknown) }
            return try handler(request)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            switch result {
            case .success(let (response, data)):
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}
