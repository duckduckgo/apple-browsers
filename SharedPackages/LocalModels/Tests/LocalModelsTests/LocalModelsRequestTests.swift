//
//  LocalModelsRequestTests.swift
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
@testable import LocalModels

extension StubbedNetworkTests {

    @Suite
    struct LocalModelsRequestTests {

        @available(iOS 16, macOS 13, *)
        @Test("localModels session sends fixed headers and no cookies", .timeLimit(.minutes(1)))
        func sessionHeaders() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            }
            let session = URLSession.localModels(configuration: StubURLProtocol.configuration())

            _ = try await session.data(from: URL(string: "https://example.com/x")!)

            let request = try #require(StubURLProtocol.requests.first)
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "DuckDuckGo")
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "")
            #expect(session.configuration.urlCache == nil)
            #expect(session.configuration.httpShouldSetCookies == false)
        }

        @available(iOS 16, macOS 13, *)
        @Test("sha256Hex streams a file", .timeLimit(.minutes(1)))
        func sha256OfFile() throws {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("hello".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(try FileHash.sha256Hex(of: url) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        }
    }
}
