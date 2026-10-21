//
//  RouteMatchingTests.swift
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
@testable import DebugServer

final class RouteMatchingTests: XCTestCase {

    private var server: DebugHTTPServer!

    override func setUp() {
        super.setUp()
        server = DebugHTTPServer(port: 0)
    }

    override func tearDown() {
        server.stop()
        server = nil
        super.tearDown()
    }

    // MARK: - Route Registration

    func testWhenRouteRegisteredThenItCanBeAddedWithoutError() {
        server.addRoute("/test", method: .GET) { _ in
            .text("OK")
        }
    }

    func testWhenStaticRouteRegisteredThenItCanBeAddedWithoutError() {
        server.addStaticRoute("/page", htmlString: "<html><body>Hello</body></html>")
    }

    func testWhenMultipleRoutesRegisteredThenAllAreAccepted() {
        server.addRoute("/a", method: .GET) { _ in .text("A") }
        server.addRoute("/b", method: .POST) { _ in .text("B") }
        server.addRoute("/c", method: .DELETE) { _ in .empty() }
    }

    func testWhenSamePathDifferentMethodsThenBothAreRegistered() {
        server.addRoute("/resource", method: .GET) { _ in .text("get") }
        server.addRoute("/resource", method: .POST) { _ in .text("post") }
    }
}
