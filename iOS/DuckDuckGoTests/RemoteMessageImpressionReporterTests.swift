//
//  RemoteMessageImpressionReporterTests.swift
//  DuckDuckGo
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

import Combine
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class RemoteMessageImpressionReporterTests: XCTestCase {

    func testSameExposureReportsOnlyOnce() async {
        let harness = Harness()
        harness.visibleSurface = harness.surface
        harness.reporter.browserDidAppear()
        await drainScheduledCheck()

        harness.signalSurfaceChange()
        await drainScheduledCheck()

        XCTAssertEqual(harness.reportedIDs, ["message"])
    }

    func testHiddenThenVisibleSurfaceReportsAgain() async {
        let harness = Harness()
        harness.visibleSurface = harness.surface
        harness.reporter.browserDidAppear()
        await drainScheduledCheck()

        harness.visibleSurface = nil
        harness.signalSurfaceChange()
        await drainScheduledCheck()
        harness.visibleSurface = harness.surface
        harness.signalSurfaceChange()
        await drainScheduledCheck()

        XCTAssertEqual(harness.reportedIDs, ["message", "message"])
    }

    func testTabAndMessageChangesEachBeginNewExposure() async {
        let harness = Harness()
        harness.visibleSurface = harness.surface
        harness.reporter.browserDidAppear()
        await drainScheduledCheck()

        harness.tabID = "other-tab"
        harness.signalSurfaceChange()
        await drainScheduledCheck()
        harness.messageID = "other-message"
        harness.signalSurfaceChange()
        await drainScheduledCheck()

        XCTAssertEqual(harness.reportedIDs, ["message", "message", "other-message"])
    }

    func testBrowserReappearanceBeginsNewExposure() async {
        let harness = Harness()
        harness.visibleSurface = harness.surface
        harness.reporter.browserDidAppear()
        await drainScheduledCheck()

        harness.reporter.browserWillDisappear()
        harness.signalSurfaceChange()
        await drainScheduledCheck()
        XCTAssertEqual(harness.reportedIDs, ["message"])

        harness.reporter.browserDidAppear()
        await drainScheduledCheck()
        XCTAssertEqual(harness.reportedIDs, ["message", "message"])
    }

    func testSearchDismissDoesNotStartOrEndExposure() async {
        let harness = Harness()
        harness.visibleSurface = harness.dismissSurface
        harness.reporter.browserDidAppear()
        await drainScheduledCheck()
        XCTAssertTrue(harness.reportedIDs.isEmpty)

        harness.visibleSurface = harness.surface
        harness.signalSurfaceChange()
        await drainScheduledCheck()
        harness.visibleSurface = harness.dismissSurface
        harness.signalSurfaceChange()
        await drainScheduledCheck()
        harness.visibleSurface = harness.surface
        harness.signalSurfaceChange()
        await drainScheduledCheck()

        XCTAssertEqual(harness.reportedIDs, ["message"])
    }

    private func drainScheduledCheck() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class Harness {
    let notificationCenter = NotificationCenter()
    let window = UIWindow()
    let surface = UIViewController()
    let dismissSurface = UIViewController()
    var tabID = "tab"
    var messageID = "message"
    var visibleSurface: UIViewController?
    var reportedIDs: [String] = []

    lazy var reporter = RemoteMessageImpressionReporter(
        contentDidChangePublisher: Empty<Void, Never>().eraseToAnyPublisher(),
        hasCurrentMessage: { [weak self] in self != nil },
        snapshot: { [weak self] in
            guard let self else { return nil }
            return RemoteMessageImpressionReporter.Snapshot(tabID: tabID,
                                                            messageID: messageID,
                                                            window: window,
                                                            surfaceRoot: surface,
                                                            searchDismissSurface: dismissSurface)
        },
        reportVisibleMessage: { [weak self] id in
            self?.reportedIDs.append(id)
            return self != nil
        },
        notificationCenter: notificationCenter,
        messageVisibilityOverride: { [weak self] _, controller, _ in
            self?.visibleSurface === controller
        }
    )

    init() {
        reporter.observeVisibilityChanges()
    }

    func signalSurfaceChange() {
        notificationCenter.post(name: RemoteMessageImpressionReporter.remoteMessageSurfaceDidChange, object: surface)
    }
}
