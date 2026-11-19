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
@_spi(Testing) @testable import Networking

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

    func testWhenHTTPErrorResponsesAreAllowedThenStatusAndBodyAreReturned() async throws {
        for (status, body) in [(400, #"{"error":"invalid_cursor"}"#), (418, ""),
                               (429, #"{"error":"rate_limited"}"#), (500, "Internal server error")] {
            let response = HTTPURLResponse(url: HTTPURLResponse.testUrl, statusCode: status, httpVersion: nil, headerFields: nil)!
            let errorData = Data(body.utf8)
            MockURLProtocol.requestHandler = { _ in (response, errorData) }
            let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
            let request = APIRequest(configuration: configuration,
                                     requirements: [.allowHTTPErrorResponse, .requireNonEmptyData, .requireETagHeader],
                                     urlSession: mockURLSession)

            let (data, returnedResponse) = try await request.fetch()

            XCTAssertEqual(returnedResponse.statusCode, status)
            XCTAssertEqual(data, errorData)
        }
    }

    func testWhenHTTPErrorResponsesAreNotAllowedThenErrorBodyDoesNotChangeStatusError() async {
        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse.internalServerError, Data(#"{"error":"server_error"}"#.utf8))
        }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, requirements: .all, urlSession: mockURLSession)

        do {
            _ = try await request.fetch()
            XCTFail("Expected an HTTP status error")
        } catch {
            guard case APIRequest.Error.invalidStatusCode(500) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testWhenHTTPErrorResponsesAreAllowedThenCompletionReceivesErrorBody() async {
        let body = Data(#"{"error":"invalid_cursor"}"#.utf8)
        let response = HTTPURLResponse(url: HTTPURLResponse.testUrl, statusCode: 400, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.requestHandler = { _ in (response, body) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, requirements: .allowHTTPErrorResponse, urlSession: mockURLSession)
        let completed = expectation(description: "Error response returned through completion")

        request.fetch { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result?.response.statusCode, 400)
            XCTAssertEqual(result?.data, body)
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
    }

    func testWhenHTTPErrorResponsesAreAllowedThenSuccessRequirementsStillApply() async {
        MockURLProtocol.requestHandler = { _ in (HTTPURLResponse.ok, nil) }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration,
                                 requirements: [.allowHTTPErrorResponse, .requireNonEmptyData], urlSession: mockURLSession)

        do {
            _ = try await request.fetch()
            XCTFail("Expected the success response to require data")
        } catch {
            guard case APIRequest.Error.emptyData = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testWhenHTTPErrorResponsesAreAllowedThenNetworkErrorsStillThrow() async {
        MockURLProtocol.requestHandler = { _ in throw MockError.someError }
        let configuration = APIRequest.Configuration(url: HTTPURLResponse.testUrl)
        let request = APIRequest(configuration: configuration, requirements: .allowHTTPErrorResponse, urlSession: mockURLSession)

        do {
            _ = try await request.fetch()
            XCTFail("Expected a network error")
        } catch {
            guard case APIRequest.Error.urlSession = error else {
                return XCTFail("Unexpected error: \(error)")
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
