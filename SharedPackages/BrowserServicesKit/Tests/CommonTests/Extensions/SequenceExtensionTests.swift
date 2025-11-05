//
//  SequenceExtensionTests.swift
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
@testable import Common

final class SequenceExtensionTests: XCTestCase {

    // MARK: - chunkedSequence

    func testThatChunkedSequenceOfEmptySequenceReturnsEmptySequence() {
        let sequence = [Int]().chunkedSequence(into: 3)
        XCTAssertEqual(Array(sequence), [])
    }

    func testThatChunkedSequenceWithSizeLargerThanSequenceReturnsSingleChunk() {
        let sequence = [1, 2].chunkedSequence(into: 5)
        XCTAssertEqual(Array(sequence), [[1, 2]])
    }

    func testThatChunkedSequenceWithExactSizeReturnsEvenChunks() {
        let sequence = [1, 2, 3, 4, 5, 6].chunkedSequence(into: 2)
        XCTAssertEqual(Array(sequence), [[1, 2], [3, 4], [5, 6]])
    }

    func testThatChunkedSequenceWithUnevenSizeReturnsLastChunkSmaller() {
        let sequence = [1, 2, 3, 4, 5].chunkedSequence(into: 2)
        XCTAssertEqual(Array(sequence), [[1, 2], [3, 4], [5]])
    }

    func testThatChunkedSequenceWithSizeOneReturnsIndividualElements() {
        let sequence = [1, 2, 3].chunkedSequence(into: 1)
        XCTAssertEqual(Array(sequence), [[1], [2], [3]])
    }

    func testThatChunkedSequenceWorksWithAnySequence() {
        let sequence = (1...255).chunkedSequence(into: 100)
        XCTAssertEqual(Array(sequence), [Array(1...100), Array(101...200), Array(201...255)])
    }

}
