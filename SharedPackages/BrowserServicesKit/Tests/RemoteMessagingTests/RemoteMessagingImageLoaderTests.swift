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

    private let testCache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0)

    override func setUp() {
        super.setUp()
        testCache.removeAllCachedResponses()
    }

    func testLoadImageReturnsImageOnSuccess() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider(data: createValidImageData(), response: createSuccessResponse())

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)
        let image = try await loader.loadImage(from: testURL)

        XCTAssertNotNil(image)
        let requests = await mockProvider.requestedURLs
        XCTAssertEqual(requests.count, 1)
    }

    func testLoadImageThrowsOnInvalidImageData() async {
        let mockProvider = MockRemoteMessagingImageDataProvider(data: Data("not an image".utf8), response: createSuccessResponse())

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as? RemoteMessagingImageLoadingError, .invalidImageData)
        }
    }

    func testEmptyDataWithValidResponseThrowsInvalidImageData() async {
        let mockProvider = MockRemoteMessagingImageDataProvider(data: Data(), response: createSuccessResponse())

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
            let mockProvider = MockRemoteMessagingImageDataProvider(data: createValidImageData(), response: HTTPURLResponse(
                url: testURL,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!)

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
        let mockProvider = MockRemoteMessagingImageDataProvider(data: createValidImageData(), response: HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!)

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(error as? RemoteMessagingImageLoadingError, .invalidResponse)
        }
    }

    func testLoadImagePropagatesNetworkError() async {
        let mockProvider = MockRemoteMessagingImageDataProvider(error: URLError(.notConnectedToInternet))

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testConcurrentRequestsForSameURLOnlyFetchOnce() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider(data: createValidImageData(), response: createSuccessResponse(), delay: 0.1)

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        let testURL = self.testURL
        async let image1 = loader.loadImage(from: testURL)
        async let image2 = loader.loadImage(from: testURL)
        async let image3 = loader.loadImage(from: testURL)

        let results = try await [image1, image2, image3]

        XCTAssertEqual(results.count, 3)
        let requests = await mockProvider.requestedURLs
        XCTAssertEqual(requests.count, 1, "Should only fetch once for concurrent requests")
        XCTAssertTrue(results[0] === results[1], "All callers should receive the same image instance")
        XCTAssertTrue(results[1] === results[2], "All callers should receive the same image instance")
    }

    func testPendingTaskCleanupAllowsNextFetch() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider(data: createValidImageData(), response: createSuccessResponse())

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        _ = try await loader.loadImage(from: testURL)
        let requests = await mockProvider.requestedURLs
        XCTAssertEqual(requests.count, 1)

        _ = try await loader.loadImage(from: testURL)
        let subsequentRequests = await mockProvider.requestedURLs
        XCTAssertEqual(subsequentRequests.count, 2, "Should fetch again after pending task is cleaned up")
    }

    func testErrorDoesNotBlockSubsequentRequests() async throws {
        let mockProvider = MockRemoteMessagingImageDataProvider(error: URLError(.notConnectedToInternet))

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        do {
            _ = try await loader.loadImage(from: testURL)
            XCTFail("Expected error")
        } catch {
            // Expected, No-op
        }

        await mockProvider.respond(with: createValidImageData(), response: createSuccessResponse())

        let image = try await loader.loadImage(from: testURL)
        XCTAssertNotNil(image, "Should succeed after failure")
        let subsequentRequests = await mockProvider.requestedURLs
        XCTAssertEqual(subsequentRequests.count, 2)
    }

    func testPrefetchFetchesAllURLs() async {
        let expectation = expectation(description: "All prefetches called")
        expectation.expectedFulfillmentCount = 3
        let mockProvider = MockRemoteMessagingImageDataProvider(data: createValidImageData(), response: createSuccessResponse()) { expectation.fulfill() }

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        let urls = [
            URL(string: "https://example.com/image1.png")!,
            URL(string: "https://example.com/image2.png")!,
            URL(string: "https://example.com/image3.png")!
        ]

        loader.prefetch(urls)

        await fulfillment(of: [expectation], timeout: 1.0)

        let requests = await mockProvider.requestedURLs
        XCTAssertEqual(requests.count, 3, "Should fetch all URLs")
        XCTAssertEqual(Set(requests), Set(urls), "Should fetch each unique URL")
    }

    func testPrefetchWithDuplicateURLsOnlyFetchesOnce() async {
        let expectation = expectation(description: "Prefetch called")
        expectation.expectedFulfillmentCount = 1
        let mockProvider = MockRemoteMessagingImageDataProvider(data: createValidImageData(), response: createSuccessResponse()) { expectation.fulfill() }

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        let duplicateURLs = [testURL, testURL, testURL]

        loader.prefetch(duplicateURLs)

        await fulfillment(of: [expectation], timeout: 1.0)

        let requests = await mockProvider.requestedURLs
        XCTAssertEqual(requests.count, 1, "Should only fetch once for duplicate URLs")
    }

    func testPrefetchDoesNotThrowOnFailure() async {
        let expectation = expectation(description: "Prefetch called")
        let mockProvider = MockRemoteMessagingImageDataProvider(error: URLError(.notConnectedToInternet)) { expectation.fulfill() }

        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider)

        loader.prefetch([testURL])

        await fulfillment(of: [expectation], timeout: 1.0)

        let requests = await mockProvider.requestedURLs
        XCTAssertEqual(requests.count, 1)
    }

    func testCachedImageReturnsNilWhenNotCached() {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider, cache: testCache)

        let result = loader.cachedImage(for: testURL)

        XCTAssertNil(result)
    }

    func testCachedImageReturnsImageWhenCached() {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider, cache: testCache)

        let imageData = createValidImageData()
        let response = createSuccessResponse()
        let cachedResponse = CachedURLResponse(response: response, data: imageData)
        testCache.storeCachedResponse(cachedResponse, for: URLRequest(url: testURL))

        let result = loader.cachedImage(for: testURL)

        XCTAssertNotNil(result)
    }

    func testCachedImageReturnsNilForInvalidCachedData() {
        let mockProvider = MockRemoteMessagingImageDataProvider()
        let loader = RemoteMessagingImageLoader(dataProvider: mockProvider, cache: testCache)

        // Manually populate the cache with invalid data
        let invalidData = Data("not an image".utf8)
        let response = createSuccessResponse()
        let cachedResponse = CachedURLResponse(response: response, data: invalidData)
        testCache.storeCachedResponse(cachedResponse, for: URLRequest(url: testURL))

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

private actor MockRemoteMessagingImageDataProvider: RemoteMessagingImageDataProviding {
    private var result: Result<(Data, URLResponse), Error>
    private let delay: TimeInterval
    private let onRequest: @Sendable () -> Void
    private(set) var requestedURLs: [URL] = []

    init(data: Data = Data(), response: URLResponse = URLResponse(), delay: TimeInterval = 0, onRequest: @escaping @Sendable () -> Void = {}) {
        self.result = .success((data, response))
        self.delay = delay
        self.onRequest = onRequest
    }

    init(error: Error, onRequest: @escaping @Sendable () -> Void = {}) {
        self.result = .failure(error)
        self.delay = 0
        self.onRequest = onRequest
    }

    func respond(with data: Data, response: URLResponse) {
        result = .success((data, response))
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        requestedURLs.append(url)
        onRequest()
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try result.get()
    }
}
