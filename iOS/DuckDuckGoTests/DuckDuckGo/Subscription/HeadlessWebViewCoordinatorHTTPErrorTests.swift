//
//  HeadlessWebViewCoordinatorHTTPErrorTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

@Suite("Headless web view HTTP error reporting")
struct HeadlessWebViewCoordinatorHTTPErrorTests {

    private let url = URL(string: "https://duckduckgo.com/subscriptions")!

    private func response(statusCode: Int) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    @available(iOS 16, macOS 13, *)
    @Test("A main-frame 4xx/5xx response is reported when enabled", .timeLimit(.minutes(1)), arguments: [400, 404, 500, 503])
    func errorStatusIsReported(statusCode: Int) {
        let error = HeadlessWebViewCoordinator.httpError(for: response(statusCode: statusCode), isForMainFrame: true, reportsHTTPErrors: true)

        #expect(error?.statusCode == statusCode)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Successful and redirect responses are not reported", .timeLimit(.minutes(1)), arguments: [200, 204, 301, 302, 399])
    func nonErrorStatusIsNotReported(statusCode: Int) {
        #expect(HeadlessWebViewCoordinator.httpError(for: response(statusCode: statusCode), isForMainFrame: true, reportsHTTPErrors: true) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Sub-frame errors are not reported", .timeLimit(.minutes(1)))
    func subFrameErrorIsNotReported() {
        #expect(HeadlessWebViewCoordinator.httpError(for: response(statusCode: 500), isForMainFrame: false, reportsHTTPErrors: true) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Nothing is reported when the setting is off", .timeLimit(.minutes(1)))
    func disabledReportsNothing() {
        #expect(HeadlessWebViewCoordinator.httpError(for: response(statusCode: 404), isForMainFrame: true, reportsHTTPErrors: false) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Non-HTTP responses are not reported", .timeLimit(.minutes(1)))
    func nonHTTPResponseIsNotReported() {
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)

        #expect(HeadlessWebViewCoordinator.httpError(for: response, isForMainFrame: true, reportsHTTPErrors: true) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The reported error carries the status code as its NSError code", .timeLimit(.minutes(1)))
    func errorBridgesStatusCode() {
        let error = HeadlessWebViewHTTPError(statusCode: 404) as NSError

        #expect(error.domain == "com.duckduckgo.headlessWebView")
        #expect(error.code == 404)
    }
}
