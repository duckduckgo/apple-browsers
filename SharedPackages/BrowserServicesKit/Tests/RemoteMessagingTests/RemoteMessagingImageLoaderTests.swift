//
//  RemoteMessagingImageLoaderTests.swift
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

import XCTest
@testable import RemoteMessaging

final class RemoteMessagingImageLoaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLCache.shared.removeAllCachedResponses()
    }

    func testLoadImageReturnsImageOnSuccess() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = createValidImageData()
        mockProvider.mockResponse = createSuccessResponse()

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)
        let image = try await loader.loadImage(from: testURL)

        XCTAssertNotNil(image)
        XCTAssertEqual(mockProvider.dataCallCount, 1)
    }

    func testLoadImageThrowsOnInvalidImageData() async {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = Data("not an image".utf8)
        mockProvider.mockResponse = createSuccessResponse()

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as? RemoteMessagingImageLoadingError, .invalidImageData)
        }
    }

    func testEmptyDataWithValidResponseThrowsInvalidImageData() async {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = Data()
        mockProvider.mockResponse = createSuccessResponse()

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected invalidImageData error")
        } catch let error as RemoteMessagingImageLoadingError {
            XCTAssertEqual(error, .invalidImageData)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLoadImageThrowsOnBadStatusCode() async {
        let badStatusCodes = [300, 301, 400, 404, 429, 500, 503]

        for statusCode in badStatusCodes {
            let mockProvider = MockRemoteMessagingImageDataProvider()
            mockProvider.mockData = createValidImageData()
            mockProvider.mockResponse = HTTPURLResponse(
                url: testURL,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )

            let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

            do {
                _ = try await loader.loadImage(from: testURL)
                XCTFail("Expected error to be thrown for status code \(statusCode)")
            } catch {
                XCTAssertEqual(
                    error as? RemoteMessagingImageLoadingError,
                    .invalidResponse,
                    "Expected .invalidResponse for status code \(statusCode)"
                )
            }
        }
    }

    func testLoadImageThrowsOnNonImageContentType() async {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = createValidImageData()
        mockProvider.mockResponse = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as? RemoteMessagingImageLoadingError, .invalidResponse)
        }
    }

    func testLoadImagePropagatesNetworkError() async {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockError = URLError(.notConnectedToInternet)

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testConcurrentRequestsForSameURLOnlyFetchOnce() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = createValidImageData()
        mockProvider.mockResponse = createSuccessResponse()

        mockProvider.delay = 0.1

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        async let image1 = loader.loadImage(from: testURL)
        async let image2 = loader.loadImage(from: testURL)
        async let image3 = loader.loadImage(from: testURL)

        let results = try await [image1, image2, image3]

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(mockProvider.dataCallCount, 1, "Should only fetch once for concurrent requests")
        XCTAssertTrue(results[0] === results[1], "All callers should receive the same image instance")
        XCTAssertTrue(results[1] === results[2], "All callers should receive the same image instance")
    }

    func testPendingTaskCleanupAllowsNextFetch() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = createValidImageData()
        mockProvider.mockResponse = createSuccessResponse()

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        _ = try await loader.loadImage(from: testURL)
        XCTAssertEqual(mockProvider.dataCallCount, 1)

        _ = try await loader.loadImage(from: testURL)
        XCTAssertEqual(mockProvider.dataCallCount, 2, "Should fetch again after pending task is cleaned up")
    }

    func testErrorDoesNotBlockSubsequentRequests() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockError = URLError(.notConnectedToInternet)

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error")
        } catch {
            // Expected, No-op
        }

        mockProvider.mockError = nil
        mockProvider.mockData = createValidImageData()
        mockProvider.mockResponse = createSuccessResponse()

        let image = try await loader.loadImage(from: testURL)
        XCTAssertNotNil(image, "Should succeed after failure")
        XCTAssertEqual(mockProvider.dataCallCount, 2)
    }

    func testPrefetchFetchesAllURLs() async {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = createValidImageData()
        mockProvider.mockResponse = createSuccessResponse()

        let expectation = expectation(description: "All prefetches called")
        expectation.expectedFulfillmentCount = 3
        mockProvider.onDataCalled = { expectation.fulfill() }

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        let urls = [
            URL(string: "https://example.com/image1.png")!,
            URL(string: "https://example.com/image2.png")!,
            URL(string: "https://example.com/image3.png")!
        ]

        loader.prefetch(urls)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(mockProvider.dataCallCount, 3, "Should fetch all URLs")
        XCTAssertEqual(Set(mockProvider.requestedURLs), Set(urls), "Should fetch each unique URL")
    }

    func testPrefetchWithDuplicateURLsOnlyFetchesOnce() async {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockData = createValidImageData()
        mockProvider.mockResponse = createSuccessResponse()

        let expectation = expectation(description: "Prefetch called")
        expectation.expectedFulfillmentCount = 1
        mockProvider.onDataCalled = { expectation.fulfill() }

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        let duplicateURLs = [testURL, testURL, testURL]

        loader.prefetch(duplicateURLs)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(mockProvider.dataCallCount, 1, "Should only fetch once for duplicate URLs")
    }

    func testPrefetchDoesNotThrowOnFailure() async {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        mockProvider.mockError = URLError(.notConnectedToInternet)

        let expectation = expectation(description: "Prefetch called")
        mockProvider.onDataCalled = { expectation.fulfill() }

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        loader.prefetch([testURL])

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(mockProvider.dataCallCount, 1)
    }

    func testCachedImageReturnsNilWhenNotCached() {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        let cache = URLCache(memoryCapacity: 1024, diskCapacity: 1024)
        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider, cache: cache)

        let result = loader.cachedImage(for: testURL)

        XCTAssertNil(result)
    }

    func testCachedImageReturnsImageWhenCached() {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        let cache = URLCache(memoryCapacity: 1024, diskCapacity: 1024)
        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider, cache: cache)

        let imageData = createValidImageData()
        let response = createSuccessResponse()
        let cachedResponse = CachedURLResponse(response: response, data: imageData)
        cache.storeCachedResponse(cachedResponse, for: URLRequest(url: testURL))

        let result = loader.cachedImage(for: testURL)

        XCTAssertNotNil(result)
    }

    func testCachedImageReturnsNilForInvalidCachedData() {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        let cache = URLCache(memoryCapacity: 1024, diskCapacity: 1024)
        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider, cache: cache)

        // Manually populate the cache with invalid data
        let invalidData = Data("not an image".utf8)
        let response = createSuccessResponse()
        let cachedResponse = CachedURLResponse(response: response, data: invalidData)
        cache.storeCachedResponse(cachedResponse, for: URLRequest(url: testURL))

        let result = loader.cachedImage(for: testURL)

        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private var testURL: URL {
        URL(string: "https://example.com/image.png")!
    }

    private func createValidImageData() -> Data {
        #if canImport(UIKit)
        return UIImage(systemName: "star")!.pngData()!
        #elseif canImport(AppKit)
        return NSImage(systemSymbolName: "star", accessibilityDescription: nil)!.tiffRepresentation!
        #endif
    }

    private func createSuccessResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!
    }
}

// MARK: - Mock

final class MockRemoteMessagingImageDataProvider: RemoteMessagingImageDataProviding {
    var mockData: Data?
    var mockError: Error?
    var mockResponse: URLResponse?
    var delay: TimeInterval = 0
    var dataCallCount = 0
    var requestedURLs: [URL] = []
    var onDataCalled: (() -> Void)?

    func data(from url: URL) async throws -> (Data, URLResponse) {
        dataCallCount += 1
        requestedURLs.append(url)
        onDataCalled?()

        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if let error = mockError { throw error }

        let response = mockResponse ?? URLResponse()
        return (mockData ?? Data(), response)
    }
}
