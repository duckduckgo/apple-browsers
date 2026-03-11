//
//  RouteHandlerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import AutomationServer

@MainActor
final class RouteHandlerTests: XCTestCase {

    var mockProvider: MockBrowserAutomationProvider!
    var server: AutomationServerCore!

    override func setUp() async throws {
        mockProvider = MockBrowserAutomationProvider()
        server = try AutomationServerCore(provider: mockProvider, port: 59998)
    }

    override func tearDown() async throws {
        server.listener.cancel()
        server = nil
        mockProvider = nil
    }

    // MARK: - /getUrl Tests

    func testGetUrl_ReturnsCurrentURL() async {
        mockProvider.currentURL = URL(string: "https://duckduckgo.com")
        let url = URLComponents(string: "/getUrl")!

        let result = await server.handlePath(url, method: "GET")

        if case .success(let message) = result {
            XCTAssertEqual(message, "https://duckduckgo.com")
        } else {
            XCTFail("Expected success")
        }
    }

    func testGetUrl_ReturnsEmptyStringWhenNoURL() async {
        mockProvider.currentURL = nil
        let url = URLComponents(string: "/getUrl")!

        let result = await server.handlePath(url, method: "GET")

        if case .success(let message) = result {
            XCTAssertEqual(message, "")
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - /getWindowHandle Tests

    func testGetWindowHandle_ReturnsCurrentTabHandle() async {
        mockProvider.currentTabHandle = "test-handle-123"
        let url = URLComponents(string: "/getWindowHandle")!

        let result = await server.handlePath(url, method: "GET")

        if case .success(let message) = result {
            XCTAssertEqual(message, "test-handle-123")
        } else {
            XCTFail("Expected success")
        }
    }

    func testGetWindowHandle_ReturnsErrorWhenNoWindow() async {
        mockProvider.currentTabHandle = nil
        let url = URLComponents(string: "/getWindowHandle")!

        let result = await server.handlePath(url, method: "GET")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .noWindow)
        } else {
            XCTFail("Expected failure")
        }
    }

    // MARK: - /getWindowHandles Tests

    func testGetWindowHandles_ReturnsAllHandles() async {
        mockProvider.tabHandles = ["tab-1", "tab-2", "tab-3"]
        let url = URLComponents(string: "/getWindowHandles")!

        let result = await server.handlePath(url, method: "GET")

        if case .success(let message) = result {
            // Parse the JSON array
            guard let data = message.data(using: .utf8),
                  let handles = try? JSONDecoder().decode([String].self, from: data) else {
                XCTFail("Invalid JSON response")
                return
            }
            XCTAssertEqual(handles, ["tab-1", "tab-2", "tab-3"])
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - /navigate Tests

    func testNavigate_CallsProviderWithURL() async {
        let url = URLComponents(string: "/navigate?url=https%3A%2F%2Fexample.com")!

        let result = await server.handlePath(url, method: "GET")

        XCTAssertEqual(mockProvider.navigateCalled?.absoluteString, "https://example.com")
        if case .success(let message) = result {
            XCTAssertEqual(message, "done")
        } else {
            XCTFail("Expected success")
        }
    }

    func testNavigate_ReturnsErrorForMissingURL() async {
        let url = URLComponents(string: "/navigate")!

        let result = await server.handlePath(url, method: "GET")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .invalidURL)
        } else {
            XCTFail("Expected failure")
        }
    }

    func testNavigate_ReturnsErrorWhenNoWindow() async {
        mockProvider.navigateResult = false
        let url = URLComponents(string: "/navigate?url=https%3A%2F%2Fexample.com")!

        let result = await server.handlePath(url, method: "GET")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .noWindow)
        } else {
            XCTFail("Expected failure")
        }
    }

    // MARK: - /closeWindow Tests

    func testCloseWindow_CallsCloseCurrentTab() async {
        let url = URLComponents(string: "/closeWindow")!

        let result = await server.handlePath(url, method: "POST")

        XCTAssertTrue(mockProvider.closeCurrentTabCalled)
        if case .success(let message) = result {
            XCTAssertEqual(message, "done")
        } else {
            XCTFail("Expected success")
        }
    }

    func testCloseWindow_ReturnsErrorWhenNoWindow() async {
        mockProvider.currentTabHandle = nil
        let url = URLComponents(string: "/closeWindow")!

        let result = await server.handlePath(url, method: "POST")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .noWindow)
        } else {
            XCTFail("Expected failure")
        }
    }

    // MARK: - /switchToWindow Tests

    func testSwitchToWindow_CallsProviderWithHandle() async {
        let url = URLComponents(string: "/switchToWindow?handle=target-tab")!

        let result = await server.handlePath(url, method: "POST")

        XCTAssertEqual(mockProvider.switchToTabCalled, "target-tab")
        if case .success(let message) = result {
            XCTAssertEqual(message, "done")
        } else {
            XCTFail("Expected success")
        }
    }

    func testSwitchToWindow_ReturnsErrorForMissingHandle() async {
        let url = URLComponents(string: "/switchToWindow")!

        let result = await server.handlePath(url, method: "POST")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .invalidWindowHandle)
        } else {
            XCTFail("Expected failure")
        }
    }

    func testSwitchToWindow_ReturnsErrorWhenTabNotFound() async {
        mockProvider.switchToTabResult = false
        let url = URLComponents(string: "/switchToWindow?handle=nonexistent")!

        let result = await server.handlePath(url, method: "POST")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .tabNotFound)
        } else {
            XCTFail("Expected failure")
        }
    }

    // MARK: - /newWindow Tests

    func testNewWindow_ReturnsNewTabHandle() async {
        mockProvider.newTabResult = "new-tab-handle"
        let url = URLComponents(string: "/newWindow")!

        let result = await server.handlePath(url, method: "POST")

        XCTAssertTrue(mockProvider.newTabCalled)
        if case .success(let message) = result {
            guard let data = message.data(using: .utf8),
                  let response = try? JSONDecoder().decode([String: String].self, from: data) else {
                XCTFail("Invalid JSON response")
                return
            }
            XCTAssertEqual(response["handle"], "new-tab-handle")
            XCTAssertEqual(response["type"], "tab")
        } else {
            XCTFail("Expected success")
        }
    }

    func testNewWindow_ReturnsErrorWhenFailed() async {
        mockProvider.newTabResult = nil
        let url = URLComponents(string: "/newWindow")!

        let result = await server.handlePath(url, method: "POST")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .noWindow)
        } else {
            XCTFail("Expected failure")
        }
    }

    // MARK: - /contentBlockerReady Tests

    func testContentBlockerReady_ReturnsTrueWhenReady() async {
        mockProvider.isContentBlockerReady = true
        let url = URLComponents(string: "/contentBlockerReady")!

        let result = await server.handlePath(url, method: "GET")

        if case .success(let message) = result {
            XCTAssertEqual(message, "true")
        } else {
            XCTFail("Expected success")
        }
    }

    func testContentBlockerReady_ReturnsFalseWhenNotReady() async {
        mockProvider.isContentBlockerReady = false
        let url = URLComponents(string: "/contentBlockerReady")!

        let result = await server.handlePath(url, method: "GET")

        if case .success(let message) = result {
            XCTAssertEqual(message, "false")
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - Unknown Route Tests

    func testUnknownRoute_ReturnsError() async {
        let url = URLComponents(string: "/unknownEndpoint")!

        let result = await server.handlePath(url, method: "GET")

        if case .failure(let error) = result {
            XCTAssertEqual(error, .unknownMethod)
        } else {
            XCTFail("Expected failure")
        }
    }

    // MARK: - /execute Tests

    func testExecute_CallsProviderWithScript() async {
        mockProvider.executeScriptResult = .success(42)
        let url = URLComponents(string: "/execute?script=return%201%2B1")!

        _ = await server.handlePath(url, method: "POST")

        XCTAssertEqual(mockProvider.executeScriptCalled?.script, "return 1+1")
    }

    func testExecute_ReturnsScriptResult() async {
        mockProvider.executeScriptResult = .success(42)
        let url = URLComponents(string: "/execute?script=return%2042")!

        let result = await server.handlePath(url, method: "POST")

        if case .success(let message) = result {
            XCTAssertEqual(message, "42")
        } else {
            XCTFail("Expected success")
        }
    }
}
