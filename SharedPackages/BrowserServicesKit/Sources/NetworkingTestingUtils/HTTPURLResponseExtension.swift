//
//  HTTPURLResponseExtension.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Networking

public extension HTTPURLResponse {

    static let testEtag = "test-etag"
    static let testUrl = URL(string: "http://www.example.com")!
    static let testUserAgent = "test-user-agent"

    static let ok = HTTPURLResponse(url: testUrl,
                                    statusCode: HTTPStatusCode.ok.rawValue,
                                    httpVersion: nil,
                                    headerFields: [HTTPHeaderKey.etag: testEtag])!

    static let okNoEtag = HTTPURLResponse(url: testUrl,
                                          statusCode: HTTPStatusCode.ok.rawValue,
                                          httpVersion: nil,
                                          headerFields: [:])!

    static let notModified = HTTPURLResponse(url: testUrl,
                                             statusCode: HTTPStatusCode.notModified.rawValue,
                                             httpVersion: nil,
                                             headerFields: [HTTPHeaderKey.etag: testEtag])!

    static let internalServerError = HTTPURLResponse(url: testUrl,
                                                     statusCode: HTTPStatusCode.internalServerError.rawValue,
                                                     httpVersion: nil,
                                                     headerFields: [:])!

    static let okUserAgent = HTTPURLResponse(url: testUrl,
                                             statusCode: HTTPStatusCode.ok.rawValue,
                                             httpVersion: nil,
                                             headerFields: [HTTPHeaderKey.userAgent: testUserAgent])!
    static let unauthorised = HTTPURLResponse(url: testUrl,
                                              statusCode: HTTPStatusCode.unauthorized.rawValue,
                                              httpVersion: nil,
                                              headerFields: [:])!
}
