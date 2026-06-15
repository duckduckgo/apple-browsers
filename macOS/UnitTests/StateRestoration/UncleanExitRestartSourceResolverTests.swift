//
//  UncleanExitRestartSourceResolverTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//

import AppUpdaterShared
import Persistence
import PersistenceTestingUtils
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class UncleanExitRestartSourceResolverTests: XCTestCase {

    private var mockCrashReportDetecting: MockCrashReportDetecting!
    private var mockBuildType: MockApplicationBuildType!
    private var mockKeyValueStore: MockKeyValueFileStore!
    private var resolver: UncleanExitRestartSourceResolver!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockCrashReportDetecting = MockCrashReportDetecting()
        mockBuildType = MockApplicationBuildType()
        mockKeyValueStore = MockKeyValueFileStore()
        resolver = UncleanExitRestartSourceResolver(
            keyValueStore: mockKeyValueStore,
            crashReportDetecting: mockCrashReportDetecting,
            buildType: mockBuildType
        )
    }

    override func tearDown() {
        resolver = nil
        mockKeyValueStore = nil
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

    func testWhenCrashAndSparkleUpdateSnapshot_ThenCrashTakesPriority() {
        mockCrashReportDetecting.shouldDetectCrashReport = true
        mockBuildType.isSparkleBuild = true
        let settings = mockKeyValueStore.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        try? settings.set("1.0.0", for: \.pendingUpdateSourceVersion)
        try? settings.set("100", for: \.pendingUpdateSourceBuild)
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .crash)
    }

    func testWhenSparkleSnapshotPresentAndNoCrash_ThenReturnsAppUpdate() {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = true
        mockBuildType.isAppStoreBuild = false
        let settings = mockKeyValueStore.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        try? settings.set("1.0.0", for: \.pendingUpdateSourceVersion)
        try? settings.set("100", for: \.pendingUpdateSourceBuild)
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .appUpdate)
    }

    func testWhenSparkleSnapshotMissingSourceBuild_ThenReturnsUnknown() {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = true
        let settings = mockKeyValueStore.throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
        try? settings.set("1.0.0", for: \.pendingUpdateSourceVersion)
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .unknown)
    }

    func testWhenAppStoreBuildUpdatedAndNoCrash_ThenReturnsAppUpdate() {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = false
        mockBuildType.isAppStoreBuild = true

        XCTAssertEqual(resolver.resolve(updateStatus: .updated), .appUpdate)
        XCTAssertEqual(resolver.resolve(updateStatus: .downgraded), .appUpdate)
    }

    func testWhenNoSignals_ThenReturnsUnknown() {
        mockCrashReportDetecting.shouldDetectCrashReport = false
        mockBuildType.isSparkleBuild = true
        resolver.captureSparklePendingUpdateSnapshot()

        let result = resolver.resolve(updateStatus: .noChange)

        XCTAssertEqual(result, .unknown)
    }
}

// MARK: - Mocks

private final class MockCrashReportDetecting: CrashReportDetecting {
    var shouldDetectCrashReport = false

    func hasNewMainBrowserCrashReport() -> Bool {
        shouldDetectCrashReport
    }
}
