//
//  APIRequestV2Tests.swift
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

import XCTest
@testable import Networking
import NetworkingTestingUtils

final class APIRequestV2Tests: XCTestCase {

    func testInitializationWithValidURL() {
        let url = URL(string: "https://www.example.com")!
        let method = HTTPRequestMethod.get
        let queryItems: QueryItems = [(key: "key", value: "value")]
        let headers = APIRequestV2.HeadersV2()
        let body = "Test body".data(using: .utf8)
        let timeoutInterval: TimeInterval = 30.0
        let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
        let constraints: [APIResponseConstraints] = []

        let apiRequest = APIRequestV2(url: url,
                                      method: method,
                                      queryItems: queryItems,
                                      headers: headers,
                                      body: body,
                                      timeoutInterval: timeoutInterval,
                                      cachePolicy: cachePolicy,
                                      responseConstraints: constraints)

        guard let urlRequest = apiRequest?.urlRequest else {
            XCTFail("Nil URLRequest")
            return
        }
        XCTAssertEqual(urlRequest.url?.host, url.host)
        XCTAssertEqual(urlRequest.httpMethod, method.rawValue)

        if let urlComponents = URLComponents(url: urlRequest.url!, resolvingAgainstBaseURL: false) {
            let expectedQueryItems = queryItems.map { queryItem in
                URLQueryItem(name: queryItem.key, value: queryItem.value)
            }
            XCTAssertEqual(urlComponents.queryItems, expectedQueryItems)
        } else {
            XCTFail("Invalid URLComponents")
        }

        XCTAssertEqual(urlRequest.allHTTPHeaderFields, headers.httpHeaders)
        XCTAssertEqual(urlRequest.httpBody, body)
        XCTAssertEqual(apiRequest?.timeoutInterval, timeoutInterval)
        XCTAssertEqual(urlRequest.cachePolicy, cachePolicy)
        XCTAssertEqual(apiRequest?.responseConstraints, constraints)
    }

    func testURLRequestGeneration() {
        let url = URL(string: "https://www.example.com")!
        let method = HTTPRequestMethod.post
        let queryItems: QueryItems = [(key: "key", value: "value")]
        let headers = APIRequestV2.HeadersV2()
        let body = "Test body".data(using: .utf8)
        let timeoutInterval: TimeInterval = 30.0
        let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData

        let apiRequest = APIRequestV2(url: url,
                                      method: method,
                                      queryItems: queryItems,
                                      headers: headers,
                                      body: body,
                                      timeoutInterval: timeoutInterval,
                                      cachePolicy: cachePolicy)

        if let urlComponents = URLComponents(url: apiRequest!.urlRequest.url!, resolvingAgainstBaseURL: false) {
            let expectedQueryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
            XCTAssertEqual(urlComponents.queryItems, expectedQueryItems)
        } else {
            XCTFail("Invalid URLComponents")
        }

        XCTAssertNotNil(apiRequest)
        XCTAssertEqual(apiRequest?.urlRequest.url?.absoluteString, "https://www.example.com?key=value")
        XCTAssertEqual(apiRequest?.urlRequest.httpMethod, method.rawValue)
        XCTAssertEqual(apiRequest?.urlRequest.allHTTPHeaderFields, headers.httpHeaders)
        XCTAssertEqual(apiRequest?.urlRequest.httpBody, body)
        XCTAssertEqual(apiRequest?.urlRequest.timeoutInterval, timeoutInterval)
        XCTAssertEqual(apiRequest?.urlRequest.cachePolicy, cachePolicy)
    }

    func testDefaultValues() {
        let url = URL(string: "https://www.example.com")!
        let apiRequest = APIRequestV2(url: url)
        let headers = APIRequestV2.HeadersV2()

        guard let urlRequest = apiRequest?.urlRequest else {
            XCTFail("Nil URLRequest")
            return
        }
        XCTAssertEqual(urlRequest.httpMethod, HTTPRequestMethod.get.rawValue)
        XCTAssertEqual(urlRequest.timeoutInterval, 60.0)
        XCTAssertEqual(headers.httpHeaders, urlRequest.allHTTPHeaderFields)
        XCTAssertNil(urlRequest.httpBody)
        XCTAssertEqual(urlRequest.cachePolicy.rawValue, 0)
        XCTAssertNil(apiRequest?.responseConstraints)
    }

    func testAllowedQueryReservedCharacters() {
        let url = URL(string: "https://www.example.com")!
        let queryItems: QueryItems = [(key: "k#e,y", value: "val#ue")]

        let apiRequest = APIRequestV2(url: url,
                                      queryItems: queryItems,
                                      allowedQueryReservedCharacters: CharacterSet(charactersIn: ","))

        let urlString = apiRequest!.urlRequest.url!.absoluteString
        XCTAssertTrue(urlString == "https://www.example.com?k%2523e,y=val%2523ue")
        let urlComponents = URLComponents(string: urlString)!
        XCTAssertTrue(urlComponents.queryItems?.count == 1)
    }

    func testQueryParametersConcatenation() {
        let url = URL(string: "https://www.example.com?originalKey=originalValue")!
        let queryItems: QueryItems = [(key: "additionalKey", value: "additionalValue")]

        let apiRequest = APIRequestV2(url: url,
                                      queryItems: queryItems,
                                      allowedQueryReservedCharacters: CharacterSet(charactersIn: ","))

        let urlString = apiRequest!.urlRequest.url!.absoluteString
        XCTAssertTrue(urlString == "https://www.example.com?originalKey=originalValue&additionalKey=additionalValue")
        let urlComponents = URLComponents(string: urlString)!
        XCTAssertTrue(urlComponents.queryItems?.count == 2)
    }
}
