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

import Foundation
import Testing

@testable import CrashReporting

struct CrashReportReaderTests {

    private let appBundleIdentifier = "com.duckduckgo.macos"
    private let vpnBundleIdentifier = "com.duckduckgo.macos.vpn.network-extension"
    private var validBundleIdentifiers: [String] {
        [appBundleIdentifier, vpnBundleIdentifier]
    }

    @Test("When files have unsupported extensions, they are ignored", .timeLimit(.minutes(1)))
    func whenFilesHaveUnsupportedExtensionsTheyAreIgnored() throws {
        let fileManager = MockFileManager()
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)
        try writeReport(named: "DuckDuckGo-legacy.crash", contents: sampleLegacyReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)
        try writeReport(named: "DuckDuckGo-unexpected.txt", contents: "text", in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)

        let reader = makeReader(now: now, fileManager: fileManager)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        #expect(reports.count == 2)
        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        #expect(returnedNames == ["DuckDuckGo-valid.ips", "DuckDuckGo-legacy.crash"])
    }

    @Test("When files do not belong to app, they are filtered out", .timeLimit(.minutes(1)))
    func whenFilesDoNotBelongToAppTheyAreFilteredOut() throws {
        let fileManager = MockFileManager()
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)
        try writeReport(named: "\(vpnBundleIdentifier)-123.crash", contents: sampleLegacyReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)
        try writeReport(named: "OtherApp.crash", contents: sampleLegacyReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)

        let reader = makeReader(now: now, fileManager: fileManager)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        #expect(returnedNames == ["DuckDuckGo-valid.ips", "\(vpnBundleIdentifier)-123.crash"])
    }

    @Test("When report is older than last check, it is ignored", .timeLimit(.minutes(1)))
    func whenReportIsOlderThanLastCheckItIsIgnored() throws {
        let fileManager = MockFileManager()
        let now = Date()
        let lastCheck = now.addingTimeInterval(-120)

        try writeReport(named: "DuckDuckGo-old.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-3600), fileManager: fileManager)
        try writeReport(named: "DuckDuckGo-new.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)

        let reader = makeReader(now: now, fileManager: fileManager)
        let reports = reader.getCrashReports(since: lastCheck)

        #expect(reports.count == 1)
        #expect(reports.first?.url.lastPathComponent == "DuckDuckGo-new.ips")
    }

    @Test("Reports are loaded from user and system directories", .timeLimit(.minutes(1)))
    func reportsAreLoadedFromUserAndSystemDirectories() throws {
        let fileManager = MockFileManager()
        let now = Date()

        try writeReport(named: "DuckDuckGo-user.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)
        try writeReport(named: "DuckDuckGo-system.crash", contents: sampleLegacyReport(), in: FileManager.systemDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)

        let reader = makeReader(now: now, fileManager: fileManager)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        let returnedNames = Set(reports.map { $0.url.lastPathComponent })
        #expect(returnedNames == ["DuckDuckGo-user.ips", "DuckDuckGo-system.crash"])
    }

    @Test("When IPS bundle ID does not match, it is filtered out", .timeLimit(.minutes(1)))
    func whenIPSBundleIDDoesNotMatchItIsFilteredOut() throws {
        let fileManager = MockFileManager()
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)
        try writeReport(named: "DuckDuckGo-other.ips", contents: sampleIPSReport(bundleID: "com.example.other"), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)

        let reader = makeReader(now: now, fileManager: fileManager)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        #expect(reports.count == 1)
        #expect(reports.first?.url.lastPathComponent == "DuckDuckGo-valid.ips")
    }

    @Test("When IPS bundle ID matches VPN extension, it is included", .timeLimit(.minutes(1)))
    func whenIPSBundleIDMatchesVpnExtensionItIsIncluded() throws {
        let fileManager = MockFileManager()
        let now = Date()

        try writeReport(named: "\(vpnBundleIdentifier)-valid.ips", contents: sampleIPSReport(bundleID: vpnBundleIdentifier), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)

        let reader = makeReader(now: now, fileManager: fileManager)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        #expect(reports.count == 1)
        #expect(reports.first?.bundleID == vpnBundleIdentifier)
    }

    @Test("When IPS bundle ID has suffix, it is filtered out", .timeLimit(.minutes(1)))
    func whenIPSBundleIDHasSuffixItIsFilteredOut() throws {
        let fileManager = MockFileManager()
        let now = Date()

        try writeReport(named: "DuckDuckGo-valid.ips", contents: sampleIPSReport(), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)
        try writeReport(named: "DuckDuckGo-suffixed.ips", contents: sampleIPSReport(bundleID: "\(appBundleIdentifier).debug"), in: FileManager.userDiagnosticReports, creationDate: now.addingTimeInterval(-60), fileManager: fileManager)

        let reader = makeReader(now: now, fileManager: fileManager)
        let reports = reader.getCrashReports(since: now.addingTimeInterval(-120))

        #expect(reports.count == 1)
        #expect(reports.first?.url.lastPathComponent == "DuckDuckGo-valid.ips")
    }

    // MARK: - Helpers

    private func writeReport(named name: String,
                             contents: String,
                             in directory: URL,
                             creationDate: Date,
                             fileManager: MockFileManager) throws {
        let url = directory.appendingPathComponent(name)
        fileManager.registerFile(at: url, in: directory, contents: contents, creationDate: creationDate)
    }

    private func makeReader(now: Date, fileManager: MockFileManager) -> CrashReportReader {
        let validBundleIDs = validBundleIdentifiers
        return CrashReportReader(fileManager: fileManager,
                                 validBundleIdentifierProvider: { validBundleIDs },
                                 dateProvider: { now })
    }

    private func sampleIPSReport(bundleID: String? = nil) throws -> String {
        let bundleIDValue = bundleID ?? appBundleIdentifier
        let original = "\"bundleID\":\"com.duckduckgo.macos.browser\""
        let replacement = "\"bundleID\":\"\(bundleIDValue)\""
        return try loadExampleCrashReportContents()
            .replacingOccurrences(of: original, with: replacement, options: [], range: nil)
    }

    private func sampleLegacyReport() -> String {
        "Process: DuckDuckGo [123]"
    }

    private func loadExampleCrashReportContents() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "DuckDuckGo-ExampleCrash", withExtension: "ips"))
        return try String(contentsOf: url)
    }

}
