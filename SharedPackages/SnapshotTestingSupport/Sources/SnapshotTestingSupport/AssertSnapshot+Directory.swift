//
//  AssertSnapshot+Directory.swift
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

import Foundation
import SnapshotTesting

// Point-Free's `assertSnapshot` does not expose `snapshotDirectory` (only `verifySnapshot` does).
// This overload adds a required `snapshotDirectory:` so reference images can be redirected into the
// SnapshotReferences submodule, and mirrors the library's own reporting (verifySnapshot + recordIssue).
// `snapshotDirectory` is non-optional-defaulted so calls that pass it resolve here unambiguously,
// while calls without it keep using the library's `assertSnapshot`.
func assertSnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record: SnapshotTestingConfiguration.Record? = nil,
    snapshotDirectory: String?,
    timeout: TimeInterval = 5,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let resolvedName: String?
    if let name, let suffix = SnapshotEnvironment.currentReferenceEnvironmentSuffix() {
        resolvedName = "\(name)_\(suffix)"
    } else {
        resolvedName = name
    }

    let failure = verifySnapshot(
        of: try value(),
        as: snapshotting,
        named: resolvedName,
        record: record,
        snapshotDirectory: snapshotDirectory,
        comparisonMode: SnapshotEnvironment.currentComparisonMode(),
        exportDirectory: snapshotExportDirectory(file: filePath),
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )

    guard let message = failure else { return }
    recordSnapshotIssue(message, fileID: fileID, file: filePath, line: line, column: column)
}

func verifySnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String?,
    record: SnapshotTestingConfiguration.Record?,
    snapshotDirectory: String?,
    comparisonMode: SnapshotComparisonMode,
    exportDirectory: String?,
    timeout: TimeInterval = 5,
    fileID: StaticString,
    file filePath: StaticString,
    testName: String,
    line: UInt,
    column: UInt
) -> String? {
    var rendered: Format?
    var comparing = snapshotting
    comparing.snapshot = { value in
        snapshotting.snapshot(value).map { format in
            rendered = format
            return format
        }
    }
    if case .skipComparison = comparisonMode {
        comparing.diffing.diffV2 = { _, _ in nil }
    }

    let failure = SnapshotTesting.verifySnapshot(
        of: try value(),
        as: comparing,
        named: name,
        record: record,
        snapshotDirectory: snapshotDirectory,
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
    if failure != nil, let rendered, let exportDirectory {
        var exporting = snapshotting
        exporting.snapshot = { _ in Async(value: rendered) }
        _ = SnapshotTesting.verifySnapshot(
            of: try value(),
            as: exporting,
            named: name,
            record: .all,
            snapshotDirectory: exportDirectory,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
    return failure
}
