//
//  CrashCollectionTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@testable import Crashes
import MetricKit
import XCTest
@_spi(Testing) import Persistence
import Common

class CrashCollectionTests: XCTestCase {

    func testFirstCrashFlagSent() {
        let crashReportSender = CrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: MockKeyValueStore())
        // 2 pixels with first = true attached
        XCTAssertTrue(crashCollection.isFirstCrash)
        crashCollection.start { pixelParameters, _, _ in
            let firstFlags = pixelParameters.compactMap { $0[.first] }
            XCTAssertFalse(firstFlags.isEmpty)
        }
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])
        XCTAssertFalse(crashCollection.isFirstCrash)
    }

    func testSubsequentPixelsDontSendFirstFlag() {
        let crashReportSender = CrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: MockKeyValueStore())
        // 2 pixels with no first parameter
        crashCollection.isFirstCrash = false
        crashCollection.start { pixelParameters, _, _ in
            let firstFlags = pixelParameters.compactMap { $0[.first] }
            XCTAssertTrue(firstFlags.isEmpty)
        }
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])
        XCTAssertFalse(crashCollection.isFirstCrash)
    }

    func testCrashesOlderThanMaxAgeAreExcludedFromCrashPixels() {
        let crashReportSender = CrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: MockKeyValueStore())

        var reportedPixelParameters: [[CrashReportPixelParameter: String]] = []
        var uploadedPayloadCount = 0
        crashCollection.start(process: { payloads in
            uploadedPayloadCount = payloads.count
            return payloads.map { _ in Data() }
        }, didFindCrashReports: { pixelParameters, _, _ in
            reportedPixelParameters = pixelParameters
        })

        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [MXCrashDiagnostic()], timeStampBegin: threeDaysAgo),
            MockPayload(mockCrashes: [MXCrashDiagnostic()], timeStampBegin: tenDaysAgo)
        ])

        XCTAssertEqual(reportedPixelParameters.count, 1, "Only the crash within the age limit should be reported as a pixel")
        XCTAssertEqual(uploadedPayloadCount, 2, "Both crashes should still be uploaded regardless of age")
    }

    func testCrashesWithinMaxAgeAreReportedAsCrashPixels() {
        let crashReportSender = CrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: MockKeyValueStore())

        var reportedPixelParameters: [[CrashReportPixelParameter: String]] = []
        crashCollection.start { pixelParameters, _, _ in
            reportedPixelParameters = pixelParameters
        }

        let sixDaysAgo = Date().addingTimeInterval(-6 * 24 * 60 * 60)
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [MXCrashDiagnostic()], timeStampBegin: sixDaysAgo)
        ])

        XCTAssertEqual(reportedPixelParameters.count, 1)
    }

    func testFirstCrashFlagIsRetainedUntilAnInWindowCrashIsReported() {
        let crashReportSender = CrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: MockKeyValueStore())

        var reportedPixelParameters: [[CrashReportPixelParameter: String]] = []
        crashCollection.start { pixelParameters, _, _ in
            reportedPixelParameters = pixelParameters
        }

        // A batch of exclusively stale crashes fires no pixel and must not consume the first-crash flag.
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [MXCrashDiagnostic()], timeStampBegin: tenDaysAgo)
        ])
        XCTAssertTrue(reportedPixelParameters.isEmpty)
        XCTAssertTrue(crashCollection.isFirstCrash)

        // A later in-window crash should still be reported as the first crash.
        let oneDayAgo = Date().addingTimeInterval(-1 * 24 * 60 * 60)
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [MXCrashDiagnostic()], timeStampBegin: oneDayAgo)
        ])
        XCTAssertEqual(reportedPixelParameters.count, 1)
        XCTAssertEqual(reportedPixelParameters.first?[.first], "1")
        XCTAssertFalse(crashCollection.isFirstCrash)
    }

    func testCRCIDIsStoredWhenReceived() {
        let responseCRCIDValue = "CRCID Value"

        let store = MockKeyValueStore()
        let crashReportSender = MockCrashReportSender(platform: .iOS, pixelEvents: nil)
        crashReportSender.responseCRCID = responseCRCIDValue
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: store)
        let expectation = self.expectation(description: "Crash collection response")

        // Set up closures on our CrashCollection object
        crashCollection.start(process: {_ in
            return ["fake-crash-data".data(using: .utf8)!]  // Not relevant to this test
        }) { pixelParameters, payloads, uploadReports in
            uploadReports()
        } didFinishHandlingResponse: {
            expectation.fulfill()
        }

        // Execute crash collection (which will call our mocked CrashReportSender as well)
        XCTAssertNil(store.object(forKey: CRCIDManager.crcidKey), "CRCID should not be present in the store before crashHandler receives crashes")
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])

        self.wait(for: [expectation], timeout: 3)

        XCTAssertEqual(store.object(forKey: CRCIDManager.crcidKey) as? String, responseCRCIDValue)
    }

    func testCRCIDIsClearedWhenServerReturnsSuccessWithNoCRCID()
    {
        let store = MockKeyValueStore()
        let crashReportSender = MockCrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: store)
        let expectation = self.expectation(description: "Crash collection response")

        // Set up closures on our CrashCollection object
        crashCollection.start(process: {_ in
            return ["fake-crash-data".data(using: .utf8)!]  // Not relevant to this test
        }) { pixelParameters, payloads, uploadReports in
            uploadReports()
        } didFinishHandlingResponse: {
            expectation.fulfill()
        }

        // Execute crash collection (which will call our mocked CrashReportSender as well)
        store.set("Initial CRCID Value", forKey: CRCIDManager.crcidKey)
        XCTAssertNotNil(store.object(forKey: CRCIDManager.crcidKey))
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])

        self.wait(for: [expectation], timeout: 3)

        XCTAssertEqual(store.object(forKey: CRCIDManager.crcidKey) as! String, "", "CRCID should not be present in the store after receiving a successful response")
    }

    func testCRCIDIsRetainedWhenServerErrorIsReceived() {
        let store = MockKeyValueStore()
        let crashReportSender = MockCrashReportSender(platform: .iOS, pixelEvents: nil)
        let crashCollection = CrashCollection(crashReportSender: crashReportSender,
                                              crashCollectionStorage: store)
        let expectation = self.expectation(description: "Crash collection response")

        // Set up closures on our CrashCollection object
        crashCollection.start(process: {_ in
            return ["fake-crash-data".data(using: .utf8)!]  // Not relevant to this test
        }) { pixelParameters, payloads, uploadReports in
            uploadReports()
        } didFinishHandlingResponse: {
            expectation.fulfill()
        }

        // Execute crash collection (which will call our mocked CrashReportSender as well)
        let crcid = "Initial CRCID Value"
        store.set(crcid, forKey: CRCIDManager.crcidKey)
        crashReportSender.responseStatusCode = 500
        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MXCrashDiagnostic(),
                MXCrashDiagnostic()
            ])
        ])

        self.wait(for: [expectation], timeout: 3)

        XCTAssertEqual(store.object(forKey: CRCIDManager.crcidKey) as? String, crcid)
    }

    // MARK: - Termination Reason Tests

    func testCrashPixelIncludesNormalizedTerminationReason() {
        let crashCollection = CrashCollection(crashReportSender: CrashReportSender(platform: .iOS, pixelEvents: nil),
                                              crashCollectionStorage: MockKeyValueStore())

        var reportedPixelParameters: [[CrashReportPixelParameter: String]] = []
        crashCollection.start { pixelParameters, _, _ in
            reportedPixelParameters = pixelParameters
        }

        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MockCrashDiagnostic(terminationReason: "Namespace SPRINGBOARD, Code 0x8badf00d, scene-update watchdog transgression"),
                MockCrashDiagnostic(terminationReason: nil)
            ])
        ])

        XCTAssertEqual(reportedPixelParameters.map { $0[.terminationReason] }, ["springboard_0x8badf00d", "-1"])
    }

    func testCrashPixelIncludesWatchdogDetails() {
        let crashCollection = CrashCollection(crashReportSender: CrashReportSender(platform: .iOS, pixelEvents: nil),
                                              crashCollectionStorage: MockKeyValueStore())

        var reportedPixelParameters: [[CrashReportPixelParameter: String]] = []
        crashCollection.start { pixelParameters, _, _ in
            reportedPixelParameters = pixelParameters
        }

        crashCollection.crashHandler.didReceive([
            MockPayload(mockCrashes: [
                MockCrashDiagnostic(terminationReason: TerminationReasons.sceneCreateCPU),
                MockCrashDiagnostic(terminationReason: nil)
            ])
        ])

        XCTAssertEqual(reportedPixelParameters.count, 2)
        XCTAssertEqual(reportedPixelParameters.first?[.terminationReason], "domain10_0x8badf00d")
        XCTAssertEqual(reportedPixelParameters.first?[.watchdogEvent], "scene-create")
        XCTAssertEqual(reportedPixelParameters.first?[.watchdogLimit], "cpu")
        XCTAssertEqual(reportedPixelParameters.first?[.processVisibility], "background")
        XCTAssertEqual(reportedPixelParameters.first?[.watchdogVisibility], "background")
        XCTAssertEqual(reportedPixelParameters.last?[.watchdogEvent], "-1")
        XCTAssertEqual(reportedPixelParameters.last?[.watchdogLimit], "-1")
        XCTAssertEqual(reportedPixelParameters.last?[.processVisibility], "-1")
        XCTAssertEqual(reportedPixelParameters.last?[.watchdogVisibility], "-1")
    }

    func testTerminationReasonPixelParameters_sceneUpdateWallClockInBackground() {
        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: TerminationReasons.sceneUpdateWallClock), [
            .terminationReason: "domain10_0x8badf00d",
            .watchdogEvent: "scene-update",
            .watchdogLimit: "wall",
            .processVisibility: "background",
            .watchdogVisibility: "background"
        ])
    }

    func testTerminationReasonPixelParameters_sceneCreateCPU() {
        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: TerminationReasons.sceneCreateCPU), [
            .terminationReason: "domain10_0x8badf00d",
            .watchdogEvent: "scene-create",
            .watchdogLimit: "cpu",
            .processVisibility: "background",
            .watchdogVisibility: "background"
        ])
    }

    func testTerminationReasonPixelParameters_processExitHasNoLimit() {
        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: TerminationReasons.processExit), [
            .terminationReason: "domain10_0x8badf00d",
            .watchdogEvent: "process-exit",
            .watchdogLimit: "-1",
            .processVisibility: "unknown",
            .watchdogVisibility: "background"
        ])
    }

    func testTerminationReasonPixelParameters_foregroundProcessWithBackgroundWatchdog() {
        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: TerminationReasons.sceneUpdateForeground), [
            .terminationReason: "domain10_0x8badf00d",
            .watchdogEvent: "scene-update",
            .watchdogLimit: "wall",
            .processVisibility: "foreground",
            .watchdogVisibility: "background"
        ])
    }

    func testTerminationReasonPixelParameters_namespaceFormatHasNoWatchdogDetails() {
        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: "Namespace SPRINGBOARD, Code 0x8badf00d"), [
            .terminationReason: "springboard_0x8badf00d",
            .watchdogEvent: "-1",
            .watchdogLimit: "-1",
            .processVisibility: "-1",
            .watchdogVisibility: "-1"
        ])
    }

    func testTerminationReasonPixelParameters_withMissingReason() {
        let expected: [CrashReportPixelParameter: String] = [
            .terminationReason: "-1",
            .watchdogEvent: "-1",
            .watchdogLimit: "-1",
            .processVisibility: "-1",
            .watchdogVisibility: "-1"
        ]
        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: nil), expected)
        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: ""), expected)
    }

    func testTerminationReasonPixelParameters_withUnrecognizedValuesReportsUnknown() {
        let reason = "<RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-create watchdog transgression: "
            + "app<com.duckduckgo.mobile.ios(F1198407-B5B1-447A-88D4-BD7AF0864EFF)>:2524 exhausted disk time allowance of 9.84 seconds\n"
            + "ProcessVisibility: Back ground 2524\n"
            + "WatchdogEvent: app<com.duckduckgo.mobile.ios>:2524\n"
            + "WatchdogVisibility: \n"
            + ") reportType:CrashLog>"

        XCTAssertEqual(CrashCollection.terminationReasonPixelParameters(from: reason), [
            .terminationReason: "domain10_0x8badf00d",
            .watchdogEvent: "unknown",
            .watchdogLimit: "unknown",
            .processVisibility: "unknown",
            .watchdogVisibility: "unknown"
        ])
    }

    func testTerminationReasonPixelParameters_neverIncludeIdentifiersFromTheReason() {
        let reasons = [
            TerminationReasons.sceneUpdateWallClock,
            TerminationReasons.sceneCreateCPU,
            TerminationReasons.processExit,
            TerminationReasons.sceneUpdateForeground
        ]
        for reason in reasons {
            for value in CrashCollection.terminationReasonPixelParameters(from: reason).values {
                XCTAssertNotNil(value.range(of: #"^[a-z0-9_-]{1,32}$"#, options: .regularExpression),
                                "Unexpected characters in pixel value: \(value)")
                XCTAssertFalse(value.contains("duckduckgo"))
            }
        }
    }

    func testPixelTerminationReason_keepsOnlyNamespaceAndCode() {
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: "Namespace SPRINGBOARD, Code 0x8badf00d"), "springboard_0x8badf00d")
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: "Namespace RUNNINGBOARD, Code 0xDEAD10CC"), "runningboard_0xdead10cc")
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: "Namespace SIGNAL, Code 9"), "signal_9")
        XCTAssertEqual(
            CrashCollection.pixelTerminationReason(from: "Namespace FRONTBOARD, Code 0xc51bad03, process-launch watchdog transgression for user@example.com"),
            "frontboard_0xc51bad03"
        )
    }

    func testPixelTerminationReason_keepsOnlyDomainAndCodeFromRunningBoardContext() {
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: TerminationReasons.sceneUpdateWallClock), "domain10_0x8badf00d")
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: "<RBSTerminateContext| domain:15 code:0xDEAD10CC>"), "domain15_0xdead10cc")
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: "<RBSTerminateContext| domain:1 code:2>"), "domain1_2")
    }

    func testPixelTerminationReason_withMissingOrUnparseableReason() {
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: nil), "-1")
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: ""), "-1")
        XCTAssertEqual(CrashCollection.pixelTerminationReason(from: "Something unexpected happened"), "unknown")
    }

    // MARK: - limitCallStackTreeDepth Tests

    func testLimitCallStackTreeDepth_withZeroMaxDepth_returnsEmptyDictionary() {
        let tree: [AnyHashable: Any] = ["key": "value", "nested": ["inner": "data"]]

        let result = CrashCollection.limitCallStackTreeDepth(tree, maxDepth: 0)

        XCTAssertTrue(result.isEmpty)
    }

    func testLimitCallStackTreeDepth_withShallowTree_preservesAllContent() {
        let tree: [AnyHashable: Any] = [
            "string": "value",
            "number": 42,
            "array": [1, 2, 3]
        ]

        let result = CrashCollection.limitCallStackTreeDepth(tree, maxDepth: 5)

        XCTAssertEqual(result["string"] as? String, "value")
        XCTAssertEqual(result["number"] as? Int, 42)
        XCTAssertEqual(result["array"] as? [Int], [1, 2, 3])
    }

    func testLimitCallStackTreeDepth_withNestedDictionary_truncatesAtMaxDepth() {
        let tree: [AnyHashable: Any] = [
            "level0": "value0",
            "nested": [
                "level1": "value1",
                "deeper": [
                    "level2": "value2",
                    "evenDeeper": [
                        "level3": "value3"
                    ]
                ]
            ]
        ]

        let result = CrashCollection.limitCallStackTreeDepth(tree, maxDepth: 2)

        // Level 0 should be preserved
        XCTAssertEqual(result["level0"] as? String, "value0")

        // Level 1 nested dict should exist
        let nested = result["nested"] as? [AnyHashable: Any]
        XCTAssertNotNil(nested)
        XCTAssertEqual(nested?["level1"] as? String, "value1")

        // Level 2 should be truncated (depth 2 means levels 0 and 1 are preserved)
        XCTAssertNil(nested?["deeper"])
    }

    func testLimitCallStackTreeDepth_withArrayOfDictionaries_truncatesAtMaxDepth() {
        let tree: [AnyHashable: Any] = [
            "frames": [
                ["name": "frame1", "nested": ["deep": "value"]],
                ["name": "frame2", "nested": ["deep": "value"]]
            ]
        ]

        let result = CrashCollection.limitCallStackTreeDepth(tree, maxDepth: 2)

        let frames = result["frames"] as? [[AnyHashable: Any]]
        XCTAssertNotNil(frames)
        XCTAssertEqual(frames?.count, 2)
        XCTAssertEqual(frames?[0]["name"] as? String, "frame1")
        XCTAssertEqual(frames?[1]["name"] as? String, "frame2")
        // Nested dictionaries inside array items should be truncated at depth 2
        XCTAssertNil(frames?[0]["nested"])
        XCTAssertNil(frames?[1]["nested"])
    }

    func testLimitCallStackTreeDepth_preservesPrimitiveArrays() {
        let tree: [AnyHashable: Any] = [
            "addresses": [0x1000, 0x2000, 0x3000],
            "names": ["a", "b", "c"]
        ]

        let result = CrashCollection.limitCallStackTreeDepth(tree, maxDepth: 1)

        XCTAssertEqual(result["addresses"] as? [Int], [0x1000, 0x2000, 0x3000])
        XCTAssertEqual(result["names"] as? [String], ["a", "b", "c"])
    }

    func testLimitCallStackTreeDepth_withDeeplyNestedStructure_doesNotCauseStackOverflow() {
        // Build a deeply nested structure iteratively (simulating what could cause stack overflow)
        var tree: [AnyHashable: Any] = ["leaf": "value"]
        for i in 0..<1000 {
            tree = ["level\(i)": tree]
        }

        // This should complete without stack overflow
        let result = CrashCollection.limitCallStackTreeDepth(tree, maxDepth: 10)

        // Verify it truncated properly
        XCTAssertFalse(result.isEmpty)
    }

    func testLimitCallStackTreeDepth_withCallStackTreeStructure_limitsDepthCorrectly() {
        // Simulate a realistic callStackTree structure
        let tree: [AnyHashable: Any] = [
            "callStacks": [
                [
                    "threadAttributed": true,
                    "callStackRootFrames": [
                        [
                            "address": 123456,
                            "subFrames": [
                                [
                                    "address": 789012,
                                    "subFrames": [
                                        ["address": 345678]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let result = CrashCollection.limitCallStackTreeDepth(tree, maxDepth: 3)

        let callStacks = result["callStacks"] as? [[AnyHashable: Any]]
        XCTAssertNotNil(callStacks)
        XCTAssertEqual(callStacks?.first?["threadAttributed"] as? Bool, true)

        let rootFrames = callStacks?.first?["callStackRootFrames"] as? [[AnyHashable: Any]]
        XCTAssertNotNil(rootFrames)
        XCTAssertEqual(rootFrames?.first?["address"] as? Int, 123456)

        // subFrames should be truncated at depth 3
        XCTAssertNil(rootFrames?.first?["subFrames"])
    }
}

class MockPayload: MXDiagnosticPayload {

    var mockCrashes: [MXCrashDiagnostic]?
    let mockTimeStampBegin: Date

    init(mockCrashes: [MXCrashDiagnostic]?, timeStampBegin: Date = Date()) {
        self.mockCrashes = mockCrashes
        self.mockTimeStampBegin = timeStampBegin
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var timeStampBegin: Date {
        return mockTimeStampBegin
    }

    override var crashDiagnostics: [MXCrashDiagnostic]? {
        return mockCrashes
    }
}

class MockCrashDiagnostic: MXCrashDiagnostic {

    let mockTerminationReason: String?

    init(terminationReason: String?) {
        self.mockTerminationReason = terminationReason
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var terminationReason: String? {
        return mockTerminationReason
    }
}

class MockCrashReportSender: CrashReportSending {

    let platform: CrashCollectionPlatform
    var responseCRCID: String?
    var responseStatusCode = 200

    var pixelEvents: EventMapping<CrashReportSenderEvent>?

    required init(platform: CrashCollectionPlatform, pixelEvents: EventMapping<CrashReportSenderEvent>?) {
        self.platform = platform
    }

    func send(_ crashReportData: Data, crcid: String?, completion: @escaping (_ result: Result<Data?, Error>, _ response: HTTPURLResponse?) -> Void) {
        var responseHeaderFields: [String: String] = [:]
        if let responseCRCID {
            responseHeaderFields[CrashReportSender.httpHeaderCRCID] = responseCRCID
        }

        guard let response = HTTPURLResponse(url: URL(string: "fakeURL")!,
                                             statusCode: responseStatusCode,
                                             httpVersion: nil,
                                             headerFields: responseHeaderFields) else {
            XCTFail("Failed to create HTTPURLResponse")
            return
        }

        if responseStatusCode == 200 {
            completion(.success(nil), response) // Success with nil data
        } else {
            completion(.failure(CrashReportSenderError.submissionFailed(response)), response)
        }
    }

    func send(_ crashReportData: Data, crcid: String?) async -> (result: Result<Data?, Error>, response: HTTPURLResponse?) {
        await withCheckedContinuation { continuation in
            send(crashReportData, crcid: crcid) { result, response in
                continuation.resume(returning: (result, response))
            }
        }
    }
}

/// `MXCrashDiagnostic.terminationReason` values in the RunningBoard format, taken from iOS crash reports.
private enum TerminationReasons {

    static let sceneUpdateWallClock = "<RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression: "
        + "app<com.duckduckgo.mobile.ios(67AB8E40-7196-467C-9E18-D4203CAE9C60)>:16525 exhausted real (wall clock) time allowance of 10.00 seconds\n"
        + "ProcessVisibility: Background\n"
        + "ProcessState: Running\n"
        + "WatchdogEvent: scene-update\n"
        + "WatchdogVisibility: Background\n"
        + "WatchdogCPUStatistics: (\n"
        + "\"Elapsed total CPU time (seconds): 13.750 (user 13.750, system 0.000), 67% CPU\",\n"
        + "\"Elapsed application CPU time (seconds): 0.047, 0% CPU\"\n"
        + ") reportType:CrashLog maxTerminationResistance:Interactive>"

    static let sceneCreateCPU = "<RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-create watchdog transgression: "
        + "app<com.duckduckgo.mobile.ios(F1198407-B5B1-447A-88D4-BD7AF0864EFF)>:2524 exhausted CPU time allowance of 9.84 seconds\n"
        + "ProcessVisibility: Background\n"
        + "ProcessState: Running\n"
        + "WatchdogEvent: scene-create\n"
        + "WatchdogVisibility: Background\n"
        + "WatchdogCPUStatistics: (\n"
        + "\"Elapsed total CPU time (seconds): 59.290 (user 59.290, system 0.000), 70% CPU\",\n"
        + "\"Elapsed application CPU time (seconds): 10.107, 12% CPU\"\n"
        + ") reportType:CrashLog maxTerminationResistance:Interactive>"

    static let processExit = "<RBSTerminateContext| domain:10 code:0x8BADF00D explanation:"
        + "[app<com.duckduckgo.mobile.ios>:39452] Failed to terminate gracefully after 5.0s\n"
        + "ProcessVisibility: Unknown\n"
        + "ProcessState: Running\n"
        + "WatchdogEvent: process-exit\n"
        + "WatchdogVisibility: Background\n"
        + "WatchdogCPUStatistics: (\n"
        + "\"Elapsed total CPU time (seconds): 6.830 (user 5.750, system 1.080), 19% CPU\",\n"
        + "\"Elapsed application CPU time (seconds): 0.002, 0% CPU\"\n"
        + ")\n"
        + "ThermalInfo: (\n"
        + "\"Thermal Level:   0\",\n"
        + "\"Thermal State:   nominal\"\n"
        + ") reportType:CrashLog maxTerminationResistance:Interactive>"

    static let sceneUpdateForeground = "<RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression: "
        + "app<com.duckduckgo.mobile.ios(0380D8F2-B88D-4075-8089-EA2A845C62D9)>:64253 exhausted real (wall clock) time allowance of 10.00 seconds\n"
        + "ProcessVisibility: Foreground\n"
        + "ProcessState: Running\n"
        + "WatchdogEvent: scene-update\n"
        + "WatchdogVisibility: Background\n"
        + "WatchdogCPUStatistics: (\n"
        + "\"Elapsed total CPU time (seconds): 40.250 (user 23.790, system 16.460), 67% CPU\",\n"
        + "\"Elapsed application CPU time (seconds): 3.777, 6% CPU\"\n"
        + ")\n"
        + "ThermalInfo: (\n"
        + "\"Thermal Level:   9\",\n"
        + "\"Thermal State:   serious\"\n"
        + ") reportType:CrashLog"
}
