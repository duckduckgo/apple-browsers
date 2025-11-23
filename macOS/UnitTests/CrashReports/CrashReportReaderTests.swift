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

    private var fileManager: MockFileManager!
    private let appBundleIdentifier = "com.duckduckgo.macos"
    private let vpnBundleIdentifier = "com.duckduckgo.macos.vpn.network-extension"
    private var validBundleIdentifiers: [String] {
        [appBundleIdentifier, vpnBundleIdentifier]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = MockFileManager()
    }

    override func tearDownWithError() throws {
        fileManager = nil
        try super.tearDownWithError()
    }

    func testWhenFilesHaveUnsupportedExtensionsTheyAreIgnored() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-legacy.crash", contents: sampleLegacyReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-unexpected.txt", contents: "text", in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        XCTAssertEqual(reports.count, 2)
        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        XCTAssertEqual(returnedNames, ["DuckDuckGo-valid.ips", "DuckDuckGo-legacy.crash"])
    }

    func testWhenFilesDoNotBelongToAppTheyAreFilteredOut() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "\(vpnBundleIdentifier)-123.crash", contents: sampleLegacyReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "OtherApp.crash", contents: sampleLegacyReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        XCTAssertEqual(returnedNames, ["DuckDuckGo-valid.ips", "\(vpnBundleIdentifier)-123.crash"])
    }

    func testWhenReportIsOlderThanLastCheckItIsIgnored() throws {
        let now = Date()
        let lastCheck = now.addingTimeInterval(-120)

        try writeReport(named: "DuckDuckGo-old.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-3600))
        try writeReport(named: "DuckDuckGo-new.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: lastCheck)

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.url.lastPathComponent, "DuckDuckGo-new.ips")
    }

    func testReportsAreLoadedFromUserAndSystemDirectories() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-user.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-system.crash", contents: sampleLegacyReport(), in: FileManager.systemDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        XCTAssertEqual(returnedNames, ["DuckDuckGo-user.ips", "DuckDuckGo-system.crash"])
    }

    func testWhenIPSBundleIDDoesNotMatchItIsFilteredOut() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-other.ips", contents: sampleIPSReport(bundleID: "com.example.other"), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.url.lastPathComponent, "DuckDuckGo-valid.ips")
    }

    func testWhenIPSBundleIDMatchesVpnExtensionItIsIncluded() throws {
        let now = Date()

        try writeReport(named: "\(vpnBundleIdentifier)-valid.ips", contents: sampleIPSReport(bundleID: vpnBundleIdentifier), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.bundleID, vpnBundleIdentifier)
    }

    func testWhenIPSBundleIDHasSuffixItIsFilteredOut() throws {
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))
        try writeReport(named: "DuckDuckGo-suffixed.ips", contents: sampleIPSReport(bundleID: "\(appBundleIdentifier).debug"), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60))

        let reader = makeReader(now: now)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.url.lastPathComponent, "DuckDuckGo-valid.ips")
    }

    // MARK: - Helpers

    private func writeReport(named name: String, contents: String, in directory: URL, creationDate: Date) throws {
        let url = directory.appendingPathComponent(name)
        fileManager.registerFile(at: url, in: directory, contents: contents, creationDate: creationDate)
    }

    private func makeReader(now: Date) -> CrashReportReader {
        let validBundleIDs = validBundleIdentifiers
        return CrashReportReader(fileManager: fileManager,
                                 validBundleIdentifierProvider: { validBundleIDs },
                                 dateProvider: { now })
    }

    private func sampleIPSReport(bundleID: String? = nil) -> String {
        let bundleIDValue = bundleID ?? appBundleIdentifier
        let original = "\"bundleID\":\"com.duckduckgo.macos.browser\""
        let replacement = "\"bundleID\":\"\(bundleIDValue)\""
        return exampleCrashReportContents.replacingOccurrences(of: original, with: replacement, options: [], range: nil)
    }

    private func sampleLegacyReport() -> String {
        return "Process: DuckDuckGo [123]"
    }

    private lazy var exampleCrashReportContents: String = {
        let bundle = Bundle(for: CrashReportReaderTests.self)
        guard let url = bundle.url(forResource: "DuckDuckGo-ExampleCrash", withExtension: "ips"),
              let contents = try? String(contentsOf: url) else {
            XCTFail("Missing sample JSON crash file")
            return ""
        }
        return contents
    }()

}
