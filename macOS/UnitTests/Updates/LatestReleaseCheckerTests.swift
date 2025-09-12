//
//  LatestReleaseCheckerTests.swift
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
import Foundation
import NetworkingTestingUtils
@testable import DuckDuckGo_Privacy_Browser

final class LatestReleaseCheckerTests: XCTestCase {

    private var mockURLSession: URLSession!
    private var checker: LatestReleaseChecker!

    override func setUp() {
        super.setUp()
        // Configure MockURLProtocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockURLSession = URLSession(configuration: config)

        checker = LatestReleaseChecker(
            baseURL: "https://test.example.com/",
            urlSession: mockURLSession
        )
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        mockURLSession = nil
        checker = nil
        super.tearDown()
    }

    // MARK: - Success Cases

    func testGetLatestReleaseAvailable_whenValidResponse_returnsCorrectMetadata() async throws {
        // Given
        let expectedMetadata = ReleaseMetadata(
            latestVersion: "1.156.0",
            buildNumber: "540",
            releaseDate: "2025-09-11T10:30:00Z",
            isCritical: false
        )

        let jsonResponse = """
        {
            "latest_appstore_version": {
                "latest_version": "1.156.0",
                "build_number": "540",
                "release_date": "2025-09-11T10:30:00Z",
                "is_critical": false
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, jsonResponse.data(using: .utf8)!)
        }

        // When
        let result = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)

        // Then
        XCTAssertEqual(result.latestVersion, expectedMetadata.latestVersion)
        XCTAssertEqual(result.buildNumber, expectedMetadata.buildNumber)
        XCTAssertEqual(result.releaseDate, expectedMetadata.releaseDate)
        XCTAssertEqual(result.isCritical, expectedMetadata.isCritical)
    }

    func testGetLatestReleaseAvailable_whenCriticalRelease_returnsCorrectMetadata() async throws {
        // Given
        let jsonResponse = """
        {
            "latest_appstore_version": {
                "latest_version": "1.157.0",
                "build_number": "541",
                "release_date": "2025-09-12T14:15:00Z",
                "is_critical": true
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, jsonResponse.data(using: .utf8)!)
        }

        // When
        let result = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)

        // Then
        XCTAssertEqual(result.latestVersion, "1.157.0")
        XCTAssertEqual(result.buildNumber, "541")
        XCTAssertEqual(result.releaseDate, "2025-09-12T14:15:00Z")
        XCTAssertTrue(result.isCritical)
    }

    // MARK: - Network Error Cases

    func testGetLatestReleaseAvailable_whenNetworkError_throwsNetworkError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            throw URLError(.notConnectedToInternet)
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected network error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .networkError(let underlyingError):
                XCTAssertTrue(underlyingError is URLError)
                let urlError = underlyingError as! URLError
                XCTAssertEqual(urlError.code, .notConnectedToInternet)
            default:
                XCTFail("Expected network error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    func testGetLatestReleaseAvailable_whenTimeoutError_throwsNetworkError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            throw URLError(.timedOut)
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected timeout error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .networkError(let underlyingError):
                XCTAssertTrue(underlyingError is URLError)
                let urlError = underlyingError as! URLError
                XCTAssertEqual(urlError.code, .timedOut)
            default:
                XCTFail("Expected network error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    // MARK: - HTTP Error Cases

    func testGetLatestReleaseAvailable_when404Response_throwsHTTPError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected HTTP error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .networkError(let error):
                XCTAssertEqual(error as! URLError, URLError(.badServerResponse))
            default:
                XCTFail("Expected HTTP error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    func testGetLatestReleaseAvailable_when500Response_throwsHTTPError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected HTTP error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .networkError(let error):
                XCTAssertEqual(error as! URLError, URLError(.badServerResponse))
            default:
                XCTFail("Expected HTTP error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    func testGetLatestReleaseAvailable_when403Response_throwsHTTPError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected HTTP error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .networkError(let error):
                XCTAssertEqual(error as! URLError, URLError(.badServerResponse))
            default:
                XCTFail("Expected HTTP error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    // MARK: - JSON Parsing Error Cases

    func testGetLatestReleaseAvailable_whenInvalidJSON_throwsParsingError() async {
        // Given
        let invalidJSON = "{ invalid json }"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, invalidJSON.data(using: .utf8)!)
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected parsing error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .decodingError(let underlyingError):
                XCTAssertTrue(underlyingError is DecodingError)
            default:
                XCTFail("Expected parsing error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    func testGetLatestReleaseAvailable_whenMissingRequiredFields_throwsParsingError() async {
        // Given
        let incompleteJSON = """
        {
            "latest_appstore_version": {
                "latest_version": "1.156.0"
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, incompleteJSON.data(using: .utf8)!)
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected parsing error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .decodingError(let underlyingError):
                XCTAssertTrue(underlyingError is DecodingError)
            default:
                XCTFail("Expected parsing error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    func testGetLatestReleaseAvailable_whenWrongJSONStructure_throwsParsingError() async {
        // Given
        let wrongStructureJSON = """
        {
            "wrong_key": {
                "latest_version": "1.156.0",
                "build_number": "540",
                "release_date": "2025-09-11T10:30:00Z",
                "is_critical": false
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, wrongStructureJSON.data(using: .utf8)!)
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected parsing error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .decodingError(let underlyingError):
                XCTAssertTrue(underlyingError is DecodingError)
            default:
                XCTFail("Expected parsing error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    func testGetLatestReleaseAvailable_whenEmptyResponse_throwsParsingError() async {
        // Given
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected parsing error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .decodingError(let underlyingError):
                XCTAssertTrue(underlyingError is DecodingError)
            default:
                XCTFail("Expected parsing error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    // MARK: - Data Types Tests

    func testGetLatestReleaseAvailable_whenWrongDataTypes_throwsParsingError() async {
        // Given
        let wrongTypesJSON = """
        {
            "latest_appstore_version": {
                "latest_version": 123,
                "build_number": true,
                "release_date": "2025-09-11T10:30:00Z",
                "is_critical": "false"
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, wrongTypesJSON.data(using: .utf8)!)
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected parsing error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .decodingError(let underlyingError):
                XCTAssertTrue(underlyingError is DecodingError)
            default:
                XCTFail("Expected parsing error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    // MARK: - Edge Cases

    func testGetLatestReleaseAvailable_whenNullValues_throwsParsingError() async {
        // Given
        let nullValuesJSON = """
        {
            "latest_appstore_version": {
                "latest_version": null,
                "build_number": "540",
                "release_date": "2025-09-11T10:30:00Z",
                "is_critical": false
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, nullValuesJSON.data(using: .utf8)!)
        }

        // When & Then
        do {
            _ = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)
            XCTFail("Expected parsing error to be thrown")
        } catch let error as LatestReleaseError {
            switch error {
            case .decodingError(let underlyingError):
                XCTAssertTrue(underlyingError is DecodingError)
            default:
                XCTFail("Expected parsing error, got \(error)")
            }
        } catch {
            XCTFail("Expected LatestReleaseError, got \(error)")
        }
    }

    func testGetLatestReleaseAvailable_whenVeryLongVersionString_returnsCorrectMetadata() async throws {
        // Given
        let longVersionString = String(repeating: "1.2.3.4.5.6.7.8.9.0.", count: 50) + "1"
        let jsonResponse = """
        {
            "latest_appstore_version": {
                "latest_version": "\(longVersionString)",
                "build_number": "540",
                "release_date": "2025-09-11T10:30:00Z",
                "is_critical": false
            }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, jsonResponse.data(using: .utf8)!)
        }

        // When
        let result = try await checker.getLatestReleaseAvailable(for: .macOSAppStore)

        // Then
        XCTAssertEqual(result.latestVersion, longVersionString)
        XCTAssertEqual(result.buildNumber, "540")
        XCTAssertEqual(result.releaseDate, "2025-09-11T10:30:00Z")
        XCTAssertFalse(result.isCritical)
    }

    // MARK: - URL Construction Tests

    func testGetLatestReleaseAvailable_constructsCorrectURL() async {
        // Given
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request

            let jsonResponse = """
            {
                "latest_appstore_version": {
                    "latest_version": "1.156.0",
                    "build_number": "540",
                    "release_date": "2025-09-11T10:30:00Z",
                    "is_critical": false
                }
            }
            """

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, jsonResponse.data(using: .utf8)!)
        }

        // When
        _ = try? await checker.getLatestReleaseAvailable(for: .macOSAppStore)

        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://test.example.com/release_metadata.json")
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
    }
}
