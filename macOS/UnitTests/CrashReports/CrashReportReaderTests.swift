//
//  CrashReportReaderTests.swift
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

final class CrashReportReaderTests: XCTestCase {

    private var temporaryDirectories: [URL] = []
    private var userDirectory: URL!
    private var systemDirectory: URL!
    private let appDisplayName = "DuckDuckGo"
    private let vpnIdentifier = "com.duckduckgo.macos.vpn.network-extension"

    override func setUpWithError() throws {
        try super.setUpWithError()
        userDirectory = try makeTemporaryDirectory()
        systemDirectory = try makeTemporaryDirectory()
    }

    override func tearDown() {
        temporaryDirectories.forEach { url in
            try? FileManager.default.removeItem(at: url)
        }

        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testWhenFilesHaveUnsupportedExtensionsTheyAreIgnored() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: userDirectory, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-legacy.crash", contents: sampleLegacyReport(), in: userDirectory, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-unexpected.txt", contents: "text", in: userDirectory, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        XCTAssertEqual(reports.count, 2)
        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        XCTAssertEqual(returnedNames, ["DuckDuckGo-valid.ips", "DuckDuckGo-legacy.crash"])
    }

    func testWhenFilesDoNotBelongToAppTheyAreFilteredOut() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: userDirectory, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "\(vpnIdentifier)-123.crash", contents: sampleLegacyReport(), in: userDirectory, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "OtherApp.crash", contents: sampleLegacyReport(), in: userDirectory, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        XCTAssertEqual(returnedNames, ["DuckDuckGo-valid.ips", "\(vpnIdentifier)-123.crash"])
    }

    func testWhenReportIsOlderThanLastCheckItIsIgnored() throws {
        let now = Date()
        let lastCheck = now.addingTimeInterval(-120)

        try writeReport(named: "DuckDuckGo-old.ips", contents: sampleIPSReport(), in: userDirectory, creationDate: now.addingTimeInterval(-3600))
        try writeReport(named: "DuckDuckGo-new.ips", contents: sampleIPSReport(), in: userDirectory, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: lastCheck)

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.url.lastPathComponent, "DuckDuckGo-new.ips")
    }

    func testReportsAreLoadedFromUserAndSystemDirectories() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-user.ips", contents: sampleIPSReport(), in: userDirectory, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-system.crash", contents: sampleLegacyReport(), in: systemDirectory, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        XCTAssertEqual(returnedNames, ["DuckDuckGo-user.ips", "DuckDuckGo-system.crash"])
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func writeReport(named name: String, contents: String, in directory: URL, creationDate: Date) throws {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: url.path)
    }
    
    private func makeReader(now: Date) -> CrashReportReader {
        return CrashReportReader(fileManager: FileManager.default,
                                 userDiagnosticReportsDirectory: userDirectory,
                                 systemDiagnosticReportsDirectory: systemDirectory,
                                 currentAppDisplayName: appDisplayName,
                                 dateProvider: { now })
    }
    
    private func sampleIPSReport() -> String {
        return #"{"bundleID":"com.duckduckgo.macos","app_version":"1.0.0"}"#
    }

    private func sampleLegacyReport() -> String {
        return "Process: \(appDisplayName) [123]"
    }

}
