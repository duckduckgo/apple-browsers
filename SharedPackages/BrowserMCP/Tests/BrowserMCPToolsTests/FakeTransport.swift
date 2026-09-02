//
//  FakeTransport.swift
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
@testable import BrowserMCPTools

/// Records requests and answers from a scripted table keyed by path.
actor FakeTransport: AutomationTransport {
    struct Request: Equatable {
        let method: String
        let path: String
        let query: [String: String]
    }

    private(set) var requests: [Request] = []
    private var responses: [String: [Result<String, AutomationClientError>]] = [:]

    func stub(_ path: String, _ message: String) {
        responses[path, default: []].append(.success(message))
    }

    func stubFailure(_ path: String, _ error: AutomationClientError) {
        responses[path, default: []].append(.failure(error))
    }

    func send(method: String, path: String, query: [String: String]) async throws -> AutomationResponse {
        requests.append(Request(method: method, path: path, query: query))
        guard var queue = responses[path], !queue.isEmpty else {
            return AutomationResponse(statusCode: 200, message: "done", requestPath: path)
        }
        let next = queue.count == 1 ? queue[0] : queue.removeFirst()
        responses[path] = queue
        switch next {
        case .success(let message):
            return AutomationResponse(statusCode: 200, message: message, requestPath: path)
        case .failure(let error):
            throw error
        }
    }
}

struct FakeLauncher: BrowserLaunching {
    let recorder: LaunchRecorder

    func launch(appPath: String, port: Int, authToken: String?) throws {
        recorder.record(appPath: appPath, port: port, authToken: authToken)
    }
}

/// Synchronous recorder so a launch is visible to the test as soon as `launch` returns.
final class LaunchRecorder: @unchecked Sendable {
    struct Launch: Equatable {
        let appPath: String
        let port: Int
        let authToken: String?
    }

    private let lock = NSLock()
    private var storage: [Launch] = []

    var launches: [Launch] {
        lock.withLock { storage }
    }

    func record(appPath: String, port: Int, authToken: String?) {
        lock.withLock { storage.append(Launch(appPath: appPath, port: port, authToken: authToken)) }
    }
}
