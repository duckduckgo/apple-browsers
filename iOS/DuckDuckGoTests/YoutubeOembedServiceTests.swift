//
//  YoutubeOembedServiceTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class YoutubeOembedServiceTests: XCTestCase {

    let sut = DefaultYoutubeOembedService()

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testSuccessfulMetadataFetch() async throws {
        // Given
        MockURLProtocol.responseData = """
        {
            "title": "Test Video",
            "author_name": "Test Channel",
            "thumbnail_url": "https://test.com/thumb.jpg"
        }
        """.data(using: .utf8)!

        // When
        let result = await sut.fetchMetadata(for: "test123")

        // Then
        XCTAssertEqual(result?.title, "Test Video")
        XCTAssertEqual(result?.authorName, "Test Channel")
        XCTAssertEqual(result?.thumbnailUrl, "https://test.com/thumb.jpg")
    }

    func testFailedMetadataFetch() async {
        // Given
        MockURLProtocol.responseData = "invalid json".data(using: .utf8)!

        // When
        let result = await sut.fetchMetadata(for: "test123")

        // Then
        XCTAssertNil(result)
    }
}

private class MockURLProtocol: URLProtocol {
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(), cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
