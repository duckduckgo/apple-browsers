//
//  APIRequestTests.swift
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

import XCTest
@testable import Networking
import NetworkingTestingUtils

final class APIRequestTests: XCTestCase {

    enum MockError: Error {
        case someError
    }

    override class func setUp() {
        APIRequest.Headers.setUserAgent("")
    }

    private var mockURLSession: URLSession {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: testConfiguration)
    }

    func testWhenUrlSessionThrowsErrorThenWrappedUrlSessionErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in throw MockError.someError }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, urlSession: mockURLSession)
        do {
            _ = try await request.fetch()
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequest.Error,
                  case .urlSession = error else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    func testWhenThereIsNoDataInResponseThenEmptyDataIsReturned() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, nil) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, urlSession: mockURLSession)
        do {
            let (data, _) = try await request.fetch()
            XCTAssertEqual(data, Data())
        } catch {
            XCTFail("Unexpected error thrown: \(error).")
        }
    }

    func testWhenThereIsNoDataInResponseButItIsRequiredThenEmptyDataErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, nil) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, requirements: [.requireNonEmptyData], urlSession: mockURLSession)
        do {
            _ = try await request.fetch()
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequest.Error, case .emptyData = error else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    let privacyConfigurationData = Data("Privacy Config".utf8)

    func testWhenEtagIsMissingInResponseThenResponseIsReturned() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.okNoEtag, self.privacyConfigurationData) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, urlSession: mockURLSession)
        do {
            let (data, response) = try await request.fetch()
            XCTAssertEqual(data, self.privacyConfigurationData)
            XCTAssertNil(response.etag)
        } catch {
            XCTFail("Unexpected error thrown: \(error).")
        }
    }

    func testWhenEtagIsMissingInResponseButItIsRequiredThenMissingEtagErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.okNoEtag, self.privacyConfigurationData) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, requirements: [.requireETagHeader], urlSession: mockURLSession)
        do {
            _ = try await request.fetch()
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequest.Error, case .missingEtagInResponse = error else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    func testWhenInternalServerErrorThenInvalidStatusCodeErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.internalServerError, nil) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, urlSession: mockURLSession)
        do {
            _ = try await request.fetch()
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequest.Error, case .invalidStatusCode = error else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    func testWhenNotModifiedResponseThenInvalidResponseErrorIsThrown() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.notModified, nil) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, urlSession: mockURLSession)
        do {
            _ = try await request.fetch()
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequest.Error, case .invalidStatusCode = error else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    func testWhenNotModifiedResponseButItIsAllowedThenResponseWithNilDataIsReturned() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.notModified, nil) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, requirements: .allowHTTPNotModified, urlSession: mockURLSession)
        do {
            let (data, response) = try await request.fetch()
            XCTAssertNil(data)
            XCTAssertEqual(response.etag, HTTPURLResponse.testEtag)
        } catch {
            XCTFail("Unexpected error thrown: \(error).")
        }
    }

}
