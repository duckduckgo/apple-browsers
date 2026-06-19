//
//  UncleanExitRestartSourceResolverTests.swift
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

import AppUpdaterShared
import CrashReportingShared
import Persistence
import PersistenceTestingUtils
import XCTest

@testable import CrashReporting
@testable import DuckDuckGo_Privacy_Browser

final class UncleanExitRestartSourceResolverTests: XCTestCase {

    private var mockCrashReportDetecting: MockCrashReportDetecting!
    private var mockBuildType: MockApplicationBuildType!
    private var mockUpdateControllerSettings: MockKeyValueFileStore!
    private var resolver: UncleanExitRestartSourceResolver!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockCrashReportDetecting = MockCrashReportDetecting()
        mockBuildType = MockApplicationBuildType()
        mockUpdateControllerSettings = MockKeyValueFileStore()
        resolver = UncleanExitRestartSourceResolver(
            updateControllerSettings: mockUpdateControllerSettings.throwingKeyedStoring(),
            crashReportDetecting: mockCrashReportDetecting,
            buildType: mockBuildType
        )
    }

    override func tearDown() {
        resolver = nil
        mockUpdateControllerSettings = nil
        mockBuildType = nil
        mockCrashReportDetecting = nil
        super.tearDown()
    }

    func testWhenNewCrashReportExists_ThenReturnsCrash() {
        mockCrashReportDetecting.shouldDetectCrashReport = true
        mockBuildType.isSparkleBuild = true
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .updated)

        XCTAssertEqual(result, .crash)
    }

    func testWhenCrashAndSparkleUpdateSnapshot_ThenCrashTakesPriority() throws {
        mockCrashReportDetecting.shouldDetectCrashReport = true
        mockBuildType.isSparkleBuild = true
        let settings = mockUpdateControllerSettings.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        try settings.set("1.0.0", for: \.pendingUpdateSourceVersion)
        try settings.set("100", for: \.pendingUpdateSourceBuild)
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .crash)
    }

    func testWhenSparkleSnapshotPresentAndNoCrash_ThenReturnsAppUpdate() throws {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = true
        mockBuildType.isAppStoreBuild = false
        let settings = mockUpdateControllerSettings.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        try settings.set("1.0.0", for: \.pendingUpdateSourceVersion)
        try settings.set("100", for: \.pendingUpdateSourceBuild)
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .appUpdate)
    }

    func testWhenSparkleSnapshotMissingSourceBuild_ThenReturnsUnknown() throws {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = true
        let settings = mockUpdateControllerSettings.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        try settings.set("1.0.0", for: \.pendingUpdateSourceVersion)
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .unknown)
    }

    func testWhenAppStoreBuildUpdatedAndNoCrash_ThenReturnsUnknownWithAppUpdate() {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = false
        mockBuildType.isAppStoreBuild = true

        XCTAssertEqual(resolver.resolve(updateStatus: .updated), .unknownWithAppUpdate)
        XCTAssertEqual(resolver.resolve(updateStatus: .downgraded), .unknownWithAppUpdate)
    }

    func testWhenNoSignals_ThenReturnsUnknown() {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = true
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .unknown)
    }
}

final class MainBrowserCrashReportDetectorTests: XCTestCase {

    private let bundleIdentifier = "com.duckduckgo.macos.browser"
    private var mockBuildType: MockApplicationBuildType!

    override func setUp() {
        super.setUp()
        mockBuildType = MockApplicationBuildType()
        mockBuildType.isSparkleBuild = true
    }

    override func tearDown() {
        mockBuildType = nil
        super.tearDown()
    }

    func testWhenLastCrashReportCheckDateIsMissing_ThenReturnsFalse() {
        let settingsStore = MockKeyValueFileStore()
        let detector = MainBrowserCrashReportDetector(
            settings: settingsStore.throwingKeyedStoring(),
            buildType: mockBuildType,
            mainBundleIdentifier: bundleIdentifier
        )

        XCTAssertFalse(detector.hasNewMainBrowserCrashReport())
    }

    func testWhenMainBundleIdentifierIsMissing_ThenReturnsFalse() throws {
        let settingsStore = MockKeyValueFileStore()
        let settings = settingsStore.throwingKeyedStoring() as any ThrowingKeyedStoring<CrashReportingSettings>
        try settings.set(Date(), for: \.lastCrashReportCheckDate)
        let detector = MainBrowserCrashReportDetector(
            settings: settings,
            buildType: mockBuildType,
            mainBundleIdentifier: nil
        )

        XCTAssertFalse(detector.hasNewMainBrowserCrashReport())
    }

    func testWhenAppStoreBuild_ThenReturnsFalseWithoutReadingDiagnosticReports() throws {
        mockBuildType.isSparkleBuild = false
        mockBuildType.isAppStoreBuild = true

        let settingsStore = MockKeyValueFileStore()
        let settings = settingsStore.throwingKeyedStoring() as any ThrowingKeyedStoring<CrashReportingSettings>
        let now = Date()
        try settings.set(now.addingTimeInterval(-120), for: \.lastCrashReportCheckDate)

        let mainBundleIdentifier = bundleIdentifier
        let diagnosticReportsDirectory = FileManager.userDiagnosticReports
        let fileManager = MockFileManager()
        let reportURL = diagnosticReportsDirectory.appendingPathComponent("DuckDuckGo-new.ips")
        fileManager.registerFile(
            at: reportURL,
            in: diagnosticReportsDirectory,
            contents: #"{"bundleID":"\#(mainBundleIdentifier)"}"#,
            creationDate: now.addingTimeInterval(-60)
        )

        let reader = CrashReportReader(
            fileManager: fileManager,
            validBundleIdentifierProvider: { [mainBundleIdentifier] in [mainBundleIdentifier] },
            dateProvider: { now }
        )
        let detector = MainBrowserCrashReportDetector(
            settings: settings,
            buildType: mockBuildType,
            crashReportReader: reader,
            mainBundleIdentifier: mainBundleIdentifier
        )

        XCTAssertFalse(detector.hasNewMainBrowserCrashReport())
    }

    func testWhenNoNewCrashReportExists_ThenReturnsFalse() throws {
        let settingsStore = MockKeyValueFileStore()
        let settings = settingsStore.throwingKeyedStoring() as any ThrowingKeyedStoring<CrashReportingSettings>
        let now = Date()
        try settings.set(now.addingTimeInterval(-120), for: \.lastCrashReportCheckDate)

        let mainBundleIdentifier = bundleIdentifier
        let fileManager = MockFileManager()
        let reader = CrashReportReader(
            fileManager: fileManager,
            validBundleIdentifierProvider: { [mainBundleIdentifier] in [mainBundleIdentifier] },
            dateProvider: { now }
        )
        let detector = MainBrowserCrashReportDetector(
            settings: settings,
            buildType: mockBuildType,
            crashReportReader: reader,
            mainBundleIdentifier: mainBundleIdentifier
        )

        XCTAssertFalse(detector.hasNewMainBrowserCrashReport())
    }

    func testWhenNewCrashReportExists_ThenReturnsTrue() throws {
        let settingsStore = MockKeyValueFileStore()
        let settings = settingsStore.throwingKeyedStoring() as any ThrowingKeyedStoring<CrashReportingSettings>
        let now = Date()
        let lastCheckDate = now.addingTimeInterval(-120)
        try settings.set(lastCheckDate, for: \.lastCrashReportCheckDate)

        let mainBundleIdentifier = bundleIdentifier
        let diagnosticReportsDirectory = FileManager.userDiagnosticReports
        let fileManager = MockFileManager()
        let reportURL = diagnosticReportsDirectory.appendingPathComponent("DuckDuckGo-new.ips")
        fileManager.registerFile(
            at: reportURL,
            in: diagnosticReportsDirectory,
            contents: #"{"bundleID":"\#(mainBundleIdentifier)"}"#,
            creationDate: now.addingTimeInterval(-60)
        )

        let reader = CrashReportReader(
            fileManager: fileManager,
            validBundleIdentifierProvider: { [mainBundleIdentifier] in [mainBundleIdentifier] },
            dateProvider: { now }
        )
        let detector = MainBrowserCrashReportDetector(
            settings: settings,
            buildType: mockBuildType,
            crashReportReader: reader,
            mainBundleIdentifier: mainBundleIdentifier
        )

        XCTAssertTrue(detector.hasNewMainBrowserCrashReport())
    }
}

// MARK: - Mocks

private final class MockCrashReportDetecting: CrashReportDetecting {
    var shouldDetectCrashReport = false

    func hasNewMainBrowserCrashReport() -> Bool {
        shouldDetectCrashReport
    }
}
