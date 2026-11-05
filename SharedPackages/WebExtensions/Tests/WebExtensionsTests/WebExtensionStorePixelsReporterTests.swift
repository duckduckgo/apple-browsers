//
//  WebExtensionStorePixelsReporterTests.swift
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
final class WebExtensionStorePixelsReporterTests: XCTestCase {

    private let storage = InMemoryKeyValueStore()
    private let pixels = StorePixelsCapturingPixelFiring()
    private let window: TimeInterval = 14 * 24 * 60 * 60
    private let hour: TimeInterval = 60 * 60
    private var date = Date(timeIntervalSince1970: 1_000_000)

    func testWhenAnEnabledInstallIs14DaysOld_ThenItIsReportedAsRetained() {
        let reporter = makeReporter()
        reporter.recordInstall("a")

        date += window - 1
        reporter.reportIfDue(installedExtensions: [record("a")], pixelExtension: pixelExtension)
        XCTAssertEqual(pixels.events, [])

        date += hour
        reporter.reportIfDue(installedExtensions: [record("a")], pixelExtension: pixelExtension)
        XCTAssertEqual(pixels.events, ["retained bitwarden"])
    }

    func testWhenAnInstallIsDisabledOrRemoved_ThenItIsReportedAsChurned() {
        let reporter = makeReporter()
        reporter.recordInstall("a")
        reporter.recordInstall("b")

        date += window
        reporter.reportIfDue(installedExtensions: [record("a", isDisabled: true)], pixelExtension: pixelExtension)

        XCTAssertEqual(pixels.events, ["churned bitwarden", "churned onePassword"])
    }

    func testWhenReportsAreChecked_ThenEachInstallIsReportedOnceAcrossReporters() {
        makeReporter().recordInstall("a")

        date += window
        makeReporter().reportIfDue(installedExtensions: [record("a")], pixelExtension: pixelExtension)
        makeReporter().reportIfDue(installedExtensions: [record("a")], pixelExtension: pixelExtension)

        XCTAssertEqual(pixels.events, ["retained bitwarden"])
    }

    func testWhenCheckedAgainWithinTheHour_ThenTheCheckIsSkipped() {
        let reporter = makeReporter()
        reporter.recordInstall("a")

        date += window - hour / 2
        reporter.reportIfDue(installedExtensions: [], pixelExtension: pixelExtension)
        date += hour / 2
        reporter.reportIfDue(installedExtensions: [], pixelExtension: pixelExtension)
        XCTAssertEqual(pixels.events, [], "The install is due, but the last check was within the hour")

        date += hour / 2
        reporter.reportIfDue(installedExtensions: [], pixelExtension: pixelExtension)
        XCTAssertEqual(pixels.events, ["churned bitwarden"])
    }

    func testWhenAnExtensionIsReinstalled_ThenItsWindowRestarts() {
        let reporter = makeReporter()
        reporter.recordInstall("a")
        date += window / 2
        reporter.recordInstall("a")

        date += window / 2
        reporter.reportIfDue(installedExtensions: [record("a")], pixelExtension: pixelExtension)
        XCTAssertEqual(pixels.events, [])

        date += window / 2
        reporter.reportIfDue(installedExtensions: [record("a")], pixelExtension: pixelExtension)
        XCTAssertEqual(pixels.events, ["retained bitwarden"])
    }

    func testWhenChecked_ThenStoreExtensionsAreCountedOncePerStoreID() {
        let reporter = makeReporter()
        let manual = InstalledWebExtension(uniqueIdentifier: "manual", filename: "manual", name: nil, version: "1")

        // An update's old and new copies count once, enabled if either is.
        reporter.reportIfDue(installedExtensions: [record("a", isDisabled: true), record("a"), record("b", isDisabled: true), manual],
                             pixelExtension: pixelExtension)

        XCTAssertEqual(pixels.installedCounts, ["2 installed, 1 enabled"])
    }

    func testWhenCheckedAgainWithinTheHour_ThenTheCountIsNotSentAgain() {
        let reporter = makeReporter()

        reporter.reportIfDue(installedExtensions: [], pixelExtension: pixelExtension)
        date += hour - 1
        reporter.reportIfDue(installedExtensions: [], pixelExtension: pixelExtension)
        date += 1
        reporter.reportIfDue(installedExtensions: [], pixelExtension: pixelExtension)

        XCTAssertEqual(pixels.installedCounts, ["0 installed, 0 enabled", "0 installed, 0 enabled"])
    }

    // MARK: - Helpers

    private func makeReporter() -> WebExtensionStorePixelsReporter {
        WebExtensionStorePixelsReporter(store: WebExtensionRetentionStore(storage: storage.keyedStoring()), pixelFiring: pixels, now: { [unowned self] in date })
    }

    private func pixelExtension(_ extensionID: String) -> WebExtensionPixelExtension {
        ["a": .catalog(.bitwarden), "b": .catalog(.onePassword)][extensionID] ?? .other
    }

    private func record(_ extensionID: String, isDisabled: Bool = false) -> InstalledWebExtension {
        InstalledWebExtension(uniqueIdentifier: UUID().uuidString, filename: extensionID, name: nil, version: "1",
                              storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: extensionID),
                              isDisabled: isDisabled)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class StorePixelsCapturingPixelFiring: WebExtensionPixelFiring {
    private(set) var events: [String] = []
    private(set) var installedCounts: [String] = []

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .installedCount(let installed, let enabled):
            installedCounts.append("\(installed) installed, \(enabled) enabled")
        case .retained14Days(let pixelExtension):
            events.append("retained \(pixelExtension.parameterValue)")
        case .churned14Days(let pixelExtension):
            events.append("churned \(pixelExtension.parameterValue)")
        default:
            break
        }
    }
}
