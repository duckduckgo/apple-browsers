//
//  AssertSnapshotEnvironment.swift
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

#if canImport(Testing)
import Testing
#endif

func assertSnapshotEnvironment(
    fileID: StaticString,
    file: StaticString,
    line: UInt,
    column: UInt
) -> Bool {
    guard let message = SnapshotEnvironment.currentValidationMessage() else {
        return true
    }

    recordSnapshotIssue(message, fileID: fileID, file: file, line: line, column: column)
    return false
}

private func recordSnapshotIssue(
    _ message: String,
    fileID: StaticString,
    file: StaticString,
    line: UInt,
    column: UInt
) {
    #if canImport(Testing)
    if Test.current != nil {
        Issue.record(
            Comment(rawValue: message),
            sourceLocation: SourceLocation(
                fileID: "\(fileID)",
                filePath: "\(file)",
                line: Int(line),
                column: Int(column)
            )
        )
        return
    }
    #endif

    XCTFail(message, file: file, line: line)
}
