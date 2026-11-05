//
//  WebExtensionRetentionReporterTests.swift
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

@_spi(Testing) import Persistence
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionRetentionReporterTests: XCTestCase {

    private let keyValueStore = InMemoryThrowingKeyValueStore()
    private let pixels = RetentionCapturingPixelFiring()
    private let window: TimeInterval = 14 * 24 * 60 * 60
    private let hour: TimeInterval = 60 * 60
    private var date = Date(timeIntervalSince1970: 1_000_000)

    func testWhenAnEnabledInstallIs14DaysOld_ThenItIsReportedAsRetainedWithItsCategory() {
        let reporter = makeReporter()
        reporter.recordInstall("a")

        date += window - 1
        reporter.reportIfDue(installedExtensions: [record("a")], category: category)
        XCTAssertEqual(pixels.events, [])

        date += hour
        reporter.reportIfDue(installedExtensions: [record("a")], category: category)
        XCTAssertEqual(pixels.events, ["retained a category-a"])
    }

    func testWhenAnInstallIsDisabledOrRemoved_ThenItIsReportedAsChurned() {
        let reporter = makeReporter()
        reporter.recordInstall("a")
        reporter.recordInstall("b")

        date += window
        reporter.reportIfDue(installedExtensions: [record("a", isDisabled: true)], category: category)

        XCTAssertEqual(pixels.events, ["churned a category-a", "churned b category-b"])
    }

    func testWhenReportsAreChecked_ThenEachInstallIsReportedOnceAcrossReporters() {
        makeReporter().recordInstall("a")

        date += window
        makeReporter().reportIfDue(installedExtensions: [record("a")], category: category)
        makeReporter().reportIfDue(installedExtensions: [record("a")], category: category)

        XCTAssertEqual(pixels.events, ["retained a category-a"])
    }

    func testWhenCheckedAgainWithinTheHour_ThenTheCheckIsSkipped() {
        let reporter = makeReporter()
        reporter.recordInstall("a")

        date += window - hour / 2
        reporter.reportIfDue(installedExtensions: [], category: category)
        date += hour / 2
        reporter.reportIfDue(installedExtensions: [], category: category)
        XCTAssertEqual(pixels.events, [], "The install is due, but the last check was within the hour")

        date += hour / 2
        reporter.reportIfDue(installedExtensions: [], category: category)
        XCTAssertEqual(pixels.events, ["churned a category-a"])
    }

    func testWhenAnExtensionIsReinstalled_ThenItsWindowRestarts() {
        let reporter = makeReporter()
        reporter.recordInstall("a")
        date += window / 2
        reporter.recordInstall("a")

        date += window / 2
        reporter.reportIfDue(installedExtensions: [record("a")], category: category)
        XCTAssertEqual(pixels.events, [])

        date += window / 2
        reporter.reportIfDue(installedExtensions: [record("a")], category: category)
        XCTAssertEqual(pixels.events, ["retained a category-a"])
    }

    // MARK: - Helpers

    private func makeReporter() -> WebExtensionRetentionReporter {
        WebExtensionRetentionReporter(keyValueStore: keyValueStore, pixelFiring: pixels, now: { [unowned self] in date })
    }

    private func category(_ extensionID: String) -> String? {
        "category-\(extensionID)"
    }

    private func record(_ extensionID: String, isDisabled: Bool = false) -> InstalledWebExtension {
        InstalledWebExtension(uniqueIdentifier: UUID().uuidString, filename: extensionID, name: nil, version: "1",
                              storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: extensionID),
                              isDisabled: isDisabled)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class RetentionCapturingPixelFiring: WebExtensionPixelFiring {
    private(set) var events: [String] = []

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .retained(let extensionID, let category):
            events.append("retained \(extensionID) \(category ?? "nil")")
        case .churned(let extensionID, let category):
            events.append("churned \(extensionID) \(category ?? "nil")")
        default:
            break
        }
    }
}
