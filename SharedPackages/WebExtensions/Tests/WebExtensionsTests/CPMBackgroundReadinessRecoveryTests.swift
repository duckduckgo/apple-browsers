//
//  CPMBackgroundReadinessRecoveryTests.swift
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
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMBackgroundReadinessRecoveryTests: XCTestCase {
    private let url = URL(string: "https://example.com/page?q=one")!
    private var date = Date()
    private let pixelFiring = CapturingStartupPixelFiring()
    private var detections: Int { pixelFiring.detections }

    private func makeRecovery() -> CPMBackgroundReadinessRecovery {
        CPMBackgroundReadinessRecovery(pixelFiring: pixelFiring, now: { [unowned self] in date })
    }

    private func pendingDocument(_ recovery: CPMBackgroundReadinessRecovery, isFirstLoad: Bool = false) -> UUID {
        let id = UUID()
        recovery.backgroundStarted(id, isFirstLoad: isFirstLoad)
        recovery.navigationStarted(in: "tab")
        recovery.navigationCommitted(in: "tab", url: url)
        return id
    }

    func testFirstStartupIsDetectedOnceAndRequiresSuccessfulBackground() {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery, isFirstLoad: true)
        recovery.initializationFailed(in: "tab")
        XCTAssertEqual(detections, 0, "Successful background startup is still required")
        recovery.backgroundCompleted(id, succeeded: true)
        recovery.backgroundCompleted(id, succeeded: true)
        recovery.initializationFailed(in: "tab")
        XCTAssertEqual(detections, 1)
    }

    func testFirstStartupIsDetectedWhenFailureArrivesAfterReadiness() {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery, isFirstLoad: true)
        recovery.backgroundCompleted(id, succeeded: true)
        XCTAssertEqual(detections, 0)
        recovery.initializationFailed(in: "tab")
        XCTAssertEqual(detections, 1)
    }

    func testIdleWakeDoesNotCountAsFirstStartupDetection() {
        let recovery = makeRecovery()
        let id = pendingDocument(recovery)
        recovery.initializationFailed(in: "tab")
        recovery.backgroundCompleted(id, succeeded: true)
        XCTAssertEqual(detections, 0)
    }

    func testFirstStartupCountsEachFailedDocumentOnlyOnce() {
        let recovery = makeRecovery()
        let id = UUID()
        recovery.backgroundStarted(id, isFirstLoad: true)
        for tab in ["first", "second"] {
            recovery.navigationStarted(in: tab)
            recovery.navigationCommitted(in: tab, url: url)
            recovery.initializationFailed(in: tab)
        }
        recovery.backgroundCompleted(id, succeeded: true)
        recovery.backgroundCompleted(id, succeeded: true)
        for tab in ["first", "second"] { recovery.initializationFailed(in: tab) }
        XCTAssertEqual(detections, 2)
    }

    func testHealthyInvalidatedFailedAndExpiredFirstStartupDocumentsAreNotDetected() {
        for invalidation in 0..<6 {
            date = Date()
            let recovery = makeRecovery()
            let id = pendingDocument(recovery, isFirstLoad: true)
            switch invalidation {
            case 0: recovery.responseReceived(in: "tab")
            case 1: recovery.navigationStarted(in: "tab")
            case 2: recovery.navigationCancelled(in: "tab")
            case 3: recovery.invalidate()
            case 4: recovery.backgroundCompleted(id, succeeded: false)
            default: date.addTimeInterval(31)
            }
            recovery.initializationFailed(in: "tab")
            recovery.backgroundCompleted(id, succeeded: true)
            XCTAssertEqual(detections, 0)
        }
    }

    func testDetectionHasSeparatePIIFreeDailyCountMetadata() {
        let metadata = CPMWebExtensionPixelMetadata(event: .cpmStartupResponseMissing)
        XCTAssertEqual(metadata?.name, "web_extension_cpm_startup_response_missing")
        XCTAssertEqual(metadata?.frequency, .dailyAndCount)
        XCTAssertEqual(metadata?.parameters, [:])
    }

    func testEveryFixHasSeparatePIIFreeMetadata() {
        for fix in CPMRecoveryFix.allCases {
            let metadata = CPMWebExtensionPixelMetadata(event: .cpmRecovery(fix, outcome: .backgroundReady))
            XCTAssertEqual(metadata?.name, "web_extension_cpm_\(fix.rawValue)")
            XCTAssertEqual(metadata?.frequency, .dailyAndCount)
            XCTAssertEqual(metadata?.parameters, ["outcome": CPMRecoveryOutcome.backgroundReady.rawValue])
        }
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingStartupPixelFiring: WebExtensionPixelFiring {
    private(set) var detections = 0

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .cpmStartupResponseMissing:
            detections += 1
        default:
            XCTFail("Unexpected startup pixel: \(event)")
        }
    }
}
