//
//  APIServiceTests.swift
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

final class APIServiceTests: XCTestCase {

    private var mockURLSession: URLSession {
        let testConfiguration = URLSessionConfiguration.default
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: testConfiguration)
    }

    // MARK: - Real API calls, do not enable

    func disabled_testRealFull() async throws {
        let request = APIRequestV2(url: HTTPURLResponse.testUrl,
                                   method: .post,
                                   queryItems: [(key: "Query,Item1%Name", value: "Query,Item1%Value")],
                                   headers: APIRequestV2.HeadersV2(userAgent: "UserAgent"),
                                   body: Data(),
                                   timeoutInterval: TimeInterval(20),
                                   cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                   responseConstraints: [APIResponseConstraints.allowHTTPNotModified,
                                                          APIResponseConstraints.requireETagHeader],
                                   allowedQueryReservedCharacters: CharacterSet(charactersIn: ","))!
        let apiService = DefaultAPIService()
        let response = try await apiService.fetch(request: request)
        let responseHTML: String = try response.decodeBody()
        XCTAssertNotNil(responseHTML)
    }

    func disabled_testRealCallJSON() async throws {
//    func testRealCallJSON() async throws {
        let request = APIRequestV2(url: HTTPURLResponse.testUrl)!
        let apiService = DefaultAPIService()
        let result = try await apiService.fetch(request: request)

        XCTAssertNotNil(result.data)
        XCTAssertNotNil(result.httpResponse)

        let responseHTML: String = try result.decodeBody()
        XCTAssertNotNil(responseHTML)
    }

    func disabled_testRealCallString() async throws {
//    func testRealCallString() async throws {
        let request = APIRequestV2(url: HTTPURLResponse.testUrl)!
        let apiService = DefaultAPIService()
        let result = try await apiService.fetch(request: request)

        XCTAssertNotNil(result)
    }

    // MARK: -

    func testQueryItems() async throws {
        let qItems: QueryItems = [
            (key: "qName1", value: "qValue1"),
             (key: "qName2", value: "qValue2")]
        MockURLProtocol.requestHandler = { request in
            let urlComponents = URLComponents(string: request.url!.absoluteString)!
            XCTAssertTrue(urlComponents.queryItems!.contains(qItems.toURLQueryItems()))
            return (HTTPURLResponse.ok, nil)
        }
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, queryItems: qItems)!
        let apiService = DefaultAPIService(urlSession: mockURLSession)
        _ = try await apiService.fetch(request: request)
    }

    func testURLRequestError() async throws {
        let request = APIRequestV2(url: HTTPURLResponse.testUrl)!

        enum TestError: Error {
            case anError
        }

        MockURLProtocol.requestHandler = { request in throw TestError.anError }

        let apiService = DefaultAPIService(urlSession: mockURLSession)

        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .urlSession = error else {
                XCTFail("Unexpected error thrown: \(error.localizedDescription).")
                return
            }
        }
    }

    // MARK: - allowHTTPNotModified

    func testResponseRequirementAllowHTTPNotModifiedSuccess() async throws {
        let requirements = [APIResponseConstraints.allowHTTPNotModified ]
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, responseConstraints: requirements)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, Data()) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        let result = try await apiService.fetch(request: request)
        XCTAssertNotNil(result)
        XCTAssertEqual(result.httpResponse.statusCode, HTTPStatusCode.notModified.rawValue)
    }

    func testResponseRequirementAllowHTTPNotModifiedFailure() async throws {
        let request = APIRequestV2(url: HTTPURLResponse.testUrl)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.notModified, Data()) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .unsatisfiedRequirement(let requirement) = error,
                  requirement == APIResponseConstraints.allowHTTPNotModified
            else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    // MARK: - requireETagHeader

    func testResponseRequirementRequireETagHeaderSuccess() async throws {
        let requirements: [APIResponseConstraints] = [
            APIResponseConstraints.requireETagHeader
        ]
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, responseConstraints: requirements)!
        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, nil) } // HTTPURLResponse.ok contains etag

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        let result = try await apiService.fetch(request: request)
        XCTAssertNotNil(result)
        XCTAssertEqual(result.httpResponse.statusCode, HTTPStatusCode.ok.rawValue)
    }

    func testResponseRequirementRequireETagHeaderFailure() async throws {
        let requirements = [ APIResponseConstraints.requireETagHeader ]
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, responseConstraints: requirements)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.okNoEtag, nil) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .unsatisfiedRequirement(let requirement) = error,
                  requirement == APIResponseConstraints.requireETagHeader
            else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    // MARK: - requireUserAgent

    func testResponseRequirementRequireUserAgentSuccess() async throws {
        let requirements = [ APIResponseConstraints.requireUserAgent ]
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, responseConstraints: requirements)!

        MockURLProtocol.requestHandler = { _ in
            ( HTTPURLResponse.okUserAgent, nil)
        }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        let result = try await apiService.fetch(request: request)
        XCTAssertEqual(result.httpResponse.statusCode, HTTPStatusCode.ok.rawValue)
    }

    func testResponseRequirementRequireUserAgentFailure() async throws {
        let requirements = [ APIResponseConstraints.requireUserAgent ]
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, responseConstraints: requirements)!

        MockURLProtocol.requestHandler = { _ in ( HTTPURLResponse.ok, nil) }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        do {
            _ = try await apiService.fetch(request: request)
            XCTFail("Expected an error to be thrown")
        } catch {
            guard let error = error as? APIRequestV2.Error,
                  case .unsatisfiedRequirement(let requirement) = error,
                  requirement == APIResponseConstraints.requireUserAgent
            else {
                XCTFail("Unexpected error thrown: \(error).")
                return
            }
        }
    }

    // MARK: - Retry

    func testRetryNoDelay() async throws {
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, retryPolicy: APIRequestV2.RetryPolicy(maxRetries: 3))!
        let requestCountExpectation = expectation(description: "Request performed count")
        requestCountExpectation.expectedFulfillmentCount = 4

        MockURLProtocol.requestHandler = { request in
            requestCountExpectation.fulfill()
            throw URLError(.cannotConnectToHost)
        }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        _ = try? await apiService.fetch(request: request)

        await fulfillment(of: [requestCountExpectation], timeout: 1.0)
    }

    func testNoRetry() async throws {
        let request = APIRequestV2(url: HTTPURLResponse.testUrl)!
        let requestCountExpectation = expectation(description: "Request performed count")
        requestCountExpectation.expectedFulfillmentCount = 1

        MockURLProtocol.requestHandler = { request in
            requestCountExpectation.fulfill()
            return ( HTTPURLResponse.internalServerError, nil)
        }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        do {
            _ = try await apiService.fetch(request: request)
        }

        await fulfillment(of: [requestCountExpectation], timeout: 1.0)
    }

    // MARK: - Delays

    func testRetryFixedDelay() async throws {
        let retryPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .fixed(.seconds(2)))
        var retries = 0
        XCTAssertEqual(retryPolicy.delay.delayTimeInterval(failureRetryCount: retries), 2)
        retries = 1
        XCTAssertEqual(retryPolicy.delay.delayTimeInterval(failureRetryCount: retries), 2)
        retries = 2
        XCTAssertEqual(retryPolicy.delay.delayTimeInterval(failureRetryCount: retries), 2)
    }

    func testRetryExponentialDelay() async throws {
        let retryPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .exponential(baseDelay: 2))
        var retries = 0
        XCTAssertEqual(retryPolicy.delay.delayTimeInterval(failureRetryCount: retries), 2)
        retries = 1
        XCTAssertEqual(retryPolicy.delay.delayTimeInterval(failureRetryCount: retries), 4)
        retries = 2
        XCTAssertEqual(retryPolicy.delay.delayTimeInterval(failureRetryCount: retries), 8)
        retries = 3
        XCTAssertEqual(retryPolicy.delay.delayTimeInterval(failureRetryCount: retries), 16)
    }

    func testRetryJitterDelay() async throws {
        let retryPolicy = APIRequestV2.RetryPolicy(maxRetries: 3, delay: .jitter(backoff: .seconds(8)))
        let delay = retryPolicy.delay.delayTimeInterval(failureRetryCount: 0)
        XCTAssertTrue(delay > -1)
        XCTAssertTrue(delay < 9)
    }

    // MARK: - Refresh auth

    func testRefreshIsCalledForAuthenticatedRequest() async throws {
        let refreshCalledExpectation = expectation(description: "Refresh block called")
        refreshCalledExpectation.expectedFulfillmentCount = 1

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse.unauthorised, nil)
        }

        let request = APIRequestV2(url: HTTPURLResponse.testUrl,
                                   headers: APIRequestV2.HeadersV2(authToken: "expiredToken"))!
        let apiService = DefaultAPIService(urlSession: mockURLSession) { request in
            refreshCalledExpectation.fulfill()
            return "someToken"
        }
        _ = try await apiService.fetch(request: request)

        await fulfillment(of: [refreshCalledExpectation], timeout: 1.0)
    }

    func testRefreshIsNotCalledForUnauthenticatedRequest() async throws {
        let refreshCalledExpectation = expectation(description: "Refresh block NOT called")
        refreshCalledExpectation.isInverted = true

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse.unauthorised, nil)
        }

        let request = APIRequestV2(url: HTTPURLResponse.testUrl)!
        let apiService = DefaultAPIService(urlSession: mockURLSession) { request in
            refreshCalledExpectation.fulfill()
            return "someToken"
        }
        _ = try await apiService.fetch(request: request)

        await fulfillment(of: [refreshCalledExpectation], timeout: 1.0)
    }

    // MARK: - User agent

    func testWhenAPIRequestsSetsUserAgent() async throws {
        let requestUserAgent = "requestUserAgent"
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, headers: APIRequestV2.HeadersV2(userAgent: requestUserAgent))!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: HTTPHeaderKey.userAgent), requestUserAgent)
            return (HTTPURLResponse.ok, nil)
        }

        let apiService = DefaultAPIService(urlSession: mockURLSession)
        _ = try await apiService.fetch(request: request)
    }

    func testWhenAPIServiceSetsUserAgent() async throws {
        let serviceUserAgent = "serviceUserAgent"
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, headers: APIRequestV2.HeadersV2())!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: HTTPHeaderKey.userAgent), serviceUserAgent)
            return (HTTPURLResponse.ok, nil)
        }

        let apiService = DefaultAPIService(urlSession: mockURLSession, userAgent: serviceUserAgent)
        _ = try await apiService.fetch(request: request)
    }

    func testWhenAPIRequestsSetsUserAgentItIsNotOverridenByAPIService() async throws {
        let serviceUserAgent = "serviceUserAgent"
        let requestUserAgent = "requestUserAgent"
        let request = APIRequestV2(url: HTTPURLResponse.testUrl, headers: APIRequestV2.HeadersV2(userAgent: requestUserAgent))!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: HTTPHeaderKey.userAgent), requestUserAgent)
            return (HTTPURLResponse.ok, nil)
        }

        let apiService = DefaultAPIService(urlSession: mockURLSession, userAgent: serviceUserAgent)
        _ = try await apiService.fetch(request: request)
    }
}
