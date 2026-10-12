//
//  PageResourceLoadErrorTests.swift
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

@testable import DDGNavigation

struct PageResourceLoadErrorTests {

    @available(iOS 16, macOS 13, *)
    @Test("Errors are wrapped as-is", .timeLimit(.minutes(1)), arguments: [
        NSError(domain: NSURLErrorDomain, code: URLError.cannotFindHost.rawValue),
        NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue),
        NSError(domain: "WebKitErrorDomain", code: 102)
    ])
    func errorsAreWrapped(error: NSError) {
        #expect(PageResourceLoadError.resourceLoadError(from: error, response: nil) == .error(error))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Non-2xx status codes are captured", .timeLimit(.minutes(1)), arguments: [
        (200, nil),
        (204, nil),
        (304, PageResourceLoadError.statusCode(304)),
        (404, .statusCode(404)),
        (503, .statusCode(503))
    ])
    func statusCodesAreCaptured(statusCode: Int, expected: PageResourceLoadError?) {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)

        #expect(PageResourceLoadError.resourceLoadError(from: nil, response: response) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Missing error and response yields nil", .timeLimit(.minutes(1)))
    func missingInputsYieldNil() {
        #expect(PageResourceLoadError.resourceLoadError(from: nil, response: nil) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Errors take precedence over the response status", .timeLimit(.minutes(1)))
    func errorTakesPrecedenceOverResponse() {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)

        #expect(PageResourceLoadError.resourceLoadError(from: error, response: response) == .error(error))
    }

    @available(iOS 16, macOS 13, *)
    @Test("String value encodes domain or status code", .timeLimit(.minutes(1)))
    func stringValueEncoding() {
        #expect(PageResourceLoadError.error(NSError(domain: NSURLErrorDomain, code: -1003)).stringValue == "(NSURLErrorDomain,-1003)")
        #expect(PageResourceLoadError.statusCode(404).stringValue == "(statusCode,404)")
    }
}
