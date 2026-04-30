//
//  UnifiedToggleInputPageContextChipViewModelTests.swift
//  DuckDuckGo
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

import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputPageContextChipViewModelTests: XCTestCase {

    private var originatingURL: CurrentValueSubject<URL?, Never>!
    private var attachedURL: CurrentValueSubject<URL?, Never>!
    private var sut: UnifiedToggleInputPageContextChipViewModel!
    private var attachCalls: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        originatingURL = .init(nil)
        attachedURL = .init(nil)
        attachCalls = []
        sut = UnifiedToggleInputPageContextChipViewModel(
            originatingURLPublisher: originatingURL.eraseToAnyPublisher(),
            attachedURLPublisher: attachedURL.eraseToAnyPublisher(),
            onAttach: { [weak self] url in self?.attachCalls.append(url) }
        )
    }

    func test_initial_noURLs_chipHidden() {
        XCTAssertFalse(sut.isVisible)
    }

    func test_originatingURL_set_attachedNil_showsChip() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        XCTAssertTrue(sut.isVisible)
    }

    func test_originatingMatchesAttached_chipHidden() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        attachedURL.send(url)
        XCTAssertFalse(sut.isVisible)
    }

    func test_originatingChangesAfterAttach_chipReappears() {
        let urlA = URL(string: "https://example.com/a")!
        let urlB = URL(string: "https://example.com/b")!
        originatingURL.send(urlA)
        attachedURL.send(urlA)
        XCTAssertFalse(sut.isVisible)
        originatingURL.send(urlB)
        XCTAssertTrue(sut.isVisible)
    }

    func test_tapped_callsOnAttach_withCurrentOriginatingURL() {
        let url = URL(string: "https://example.com/a")!
        originatingURL.send(url)
        sut.tapped()
        XCTAssertEqual(attachCalls, [url])
    }

    func test_tapped_noOriginatingURL_doesNotCallOnAttach() {
        sut.tapped()
        XCTAssertTrue(attachCalls.isEmpty)
    }
}
