//
//  XCTestCaseExtension.swift
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
@testable import DuckDuckGo_Privacy_Browser

extension XCTestCase {

    /// Asserts that two NSImage objects are equal by comparing their PNG data representation
    /// - Parameters:
    ///   - actualImage: The actual image to compare
    ///   - expectedImage: The expected image to compare against
    ///   - message: Optional message to display on failure
    ///   - file: The file where the assertion is called
    ///   - line: The line where the assertion is called
    func XCTAssertImagesEqual(
        _ actualImage: NSImage?,
        _ expectedImage: NSImage?,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let message = message.isEmpty ? "" : ": \(message)"
        guard let actualImage = actualImage else {
            XCTFail("Actual image is nil. Expected: \(expectedImage?.description ?? "nil")\(message)", file: file, line: line)
            return
        }

        guard let expectedImage = expectedImage else {
            XCTFail("Expected image is nil. Actual: \(actualImage.description)\(message)", file: file, line: line)
            return
        }

        guard let actualData = actualImage.pngData(),
              let expectedData = expectedImage.pngData() else {
            XCTFail("Failed to convert images to PNG data. Actual: \(actualImage.description), Expected: \(expectedImage.description)\(message)", file: file, line: line)
            return
        }

        if actualData != expectedData {
            XCTFail("Images not equal. Actual: \(actualImage.description), Expected: \(expectedImage.description)\(message)", file: file, line: line)
        }
    }

    func reportIssue(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let testRun else {
            fatalError("testCase.testRun is nil")
        }
        // We're using private `_recordIssue:` to allow reporting issues after test run has finished
        let recordIssueSelector = NSSelectorFromString("_recordIssue:")
        let issue = XCTIssue(type: .assertionFailure, compactDescription: message, sourceCodeContext: XCTSourceCodeContext(location: XCTSourceCodeLocation(filePath: file, lineNumber: line)))
        guard testRun.responds(to: recordIssueSelector) else {
            record(issue)
            return
        }
        testRun.perform(recordIssueSelector, with: issue)
    }

}
