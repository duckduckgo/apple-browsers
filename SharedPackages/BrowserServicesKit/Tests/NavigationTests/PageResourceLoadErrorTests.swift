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
    @Test("URL errors map to their category", .timeLimit(.minutes(1)), arguments: [
        (URLError.Code.cannotFindHost, PageResourceLoadError.dns),
        (.dnsLookupFailed, .dns),
        (.timedOut, .connection),
        (.notConnectedToInternet, .connection),
        (.serverCertificateUntrusted, .certificate),
        (.clientCertificateRequired, .certificate)
    ])
    func urlErrorsAreClassified(code: URLError.Code, expected: PageResourceLoadError) {
        let error = NSError(domain: NSURLErrorDomain, code: code.rawValue)

        #expect(PageResourceLoadError.resourceLoadError(from: error, response: nil) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unclassified errors are ignored", .timeLimit(.minutes(1)), arguments: [
        NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue),
        NSError(domain: "WebKitErrorDomain", code: URLError.cannotFindHost.rawValue)
    ])
    func unclassifiedErrorsAreIgnored(error: NSError) {
        #expect(PageResourceLoadError.resourceLoadError(from: error, response: nil) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("HTTP status codes map to their category", .timeLimit(.minutes(1)), arguments: [
        (200, nil),
        (304, nil),
        (404, PageResourceLoadError.client),
        (503, .server)
    ])
    func statusCodesAreClassified(statusCode: Int, expected: PageResourceLoadError?) {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)

        #expect(PageResourceLoadError.resourceLoadError(from: nil, response: response) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Errors take precedence over the response status", .timeLimit(.minutes(1)))
    func errorTakesPrecedenceOverResponse() {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)

        #expect(PageResourceLoadError.resourceLoadError(from: error, response: response) == .connection)
    }
}
