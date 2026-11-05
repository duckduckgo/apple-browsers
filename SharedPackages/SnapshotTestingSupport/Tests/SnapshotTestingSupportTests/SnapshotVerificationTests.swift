//
//  SnapshotVerificationTests.swift
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
@testable import SnapshotTestingSupport
import Testing

@Suite("Snapshot Verification Tests")
struct SnapshotVerificationTests {

    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    private var referenceDirectory: URL { root.appendingPathComponent("references", isDirectory: true) }
    private var exportDirectory: URL { root.appendingPathComponent("exported", isDirectory: true) }
    private var referenceFile: URL { referenceDirectory.appendingPathComponent("verification.state.txt") }
    private var exportedFile: URL { exportDirectory.appendingPathComponent("verification.state.txt") }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func skippedComparisonPassesWhenReferenceDiffers() throws {
        try writeReference("reference")

        let failure = verify("rendered", comparisonMode: .skipComparison(reason: "local"))

        #expect(failure == nil)
        #expect(try contents(of: referenceFile) == "reference")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func skippedComparisonRecordsMissingReference() throws {
        let failure = verify("rendered", comparisonMode: .skipComparison(reason: "local"))

        #expect(failure?.contains("No reference was found on disk. Automatically recorded snapshot") == true)
        #expect(try contents(of: referenceFile) == "rendered")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func comparisonFailsWhenReferenceDiffers() throws {
        try writeReference("reference")

        let failure = verify("rendered", comparisonMode: .compare)

        #expect(failure?.contains("does not match reference") == true)
        #expect(try contents(of: referenceFile) == "reference")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func exportWritesRenderedSnapshotWhenComparisonFails() throws {
        try writeReference("reference")

        let failure = verify("rendered", comparisonMode: .compare, exportDirectory: exportDirectory.path)

        #expect(failure != nil)
        #expect(try contents(of: exportedFile) == "rendered")
        #expect(try contents(of: referenceFile) == "reference")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func exportWritesNothingWithoutExportDirectory() throws {
        try writeReference("rendered")

        let failure = verify("rendered", comparisonMode: .compare)

        #expect(failure == nil)
        #expect(!FileManager.default.fileExists(atPath: exportDirectory.path))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func exportDirectoryMirrorsReferenceDirectory() throws {
        let reference = try #require(snapshotReferenceDirectory(file: #filePath, environment: [:]))
        let export = try #require(snapshotExportDirectory(file: #filePath, environment: ["SNAPSHOT_EXPORT_DIR": "/tmp/rendered"]))
        let relativePath = try #require(reference.components(separatedBy: "/SnapshotReferences/").last)

        #expect(relativePath.hasSuffix("SharedPackages/SnapshotTestingSupport/Tests/SnapshotTestingSupportTests/__Snapshots__/SnapshotVerificationTests"))
        #expect(export == "/tmp/rendered/\(relativePath)")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func exportDirectoryIsNilWithoutEnvironmentVariable() {
        #expect(snapshotExportDirectory(file: #filePath, environment: [:]) == nil)
    }

    private func verify(
        _ rendered: String,
        comparisonMode: SnapshotComparisonMode,
        exportDirectory: String? = nil
    ) -> String? {
        verifySnapshot(
            of: rendered,
            as: .lines,
            named: "state",
            record: .missing,
            snapshotDirectory: referenceDirectory.path,
            comparisonMode: comparisonMode,
            exportDirectory: exportDirectory,
            fileID: #fileID,
            file: #filePath,
            testName: "verification",
            line: #line,
            column: #column
        )
    }

    private func writeReference(_ text: String) throws {
        try FileManager.default.createDirectory(at: referenceDirectory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: referenceFile)
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
