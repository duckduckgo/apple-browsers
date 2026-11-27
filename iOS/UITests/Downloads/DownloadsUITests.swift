//
//  DownloadsUITests.swift
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

import XCTest
import UITestingSupport

final class DownloadsUITests: UITestCase {

    private let timeout = UITestTimeouts.navigation

    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_DISABLE_ANIMATIONS": "1"]
    }

    func testWhenDownloadIsInProgressThenItShowsProgressAndCanBeCancelled() throws {
        let site = try localWebsite()
        var filename = ""

        XCTContext.runActivity(named: "Start a slow download") { _ in
            filename = site.startDownload(.slowFile, in: app)
            saveToDownloads()
        }

        XCTContext.runActivity(named: "The list shows the download in progress") { _ in
            openDownloads()
            XCTAssertTrue(app.staticTexts[filename].waitForExistence(timeout: timeout))
            let progress = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Downloading")).firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: timeout), "The ongoing download shows no progress.")
        }

        XCTContext.runActivity(named: "Cancel the download") { _ in
            app.cells.containing(.staticText, identifier: filename).buttons["Cancel"].tapWhenHittable(in: app)
            let alert = app.alerts["Cancel download?"]
            XCTAssertTrue(alert.waitForExistence(timeout: timeout))
            alert.buttons["Yes"].tap()
            XCTAssertTrue(app.staticTexts[filename].waitForNonExistence(timeout: timeout),
                          "The cancelled download is still listed.")
        }
    }

    func testWhenDownloadCompletesThenItCanBeSharedPreviewedAndDeleted() throws {
        let site = try localWebsite()
        var filename = ""

        XCTContext.runActivity(named: "Download a PDF") { _ in
            filename = site.startDownload(.pdf, in: app)
            saveToDownloads()
            openDownloads()
            XCTAssertTrue(app.staticTexts[filename].waitForExistence(timeout: timeout))
        }
        let row = app.cells.containing(.staticText, identifier: filename).firstMatch

        XCTContext.runActivity(named: "Share the file") { _ in
            row.buttons["Share"].tapWhenHittable(in: app)
            let shareTarget = app.otherElements["ActivityListView"].cells["shareCell"].firstMatch
            XCTAssertTrue(shareTarget.waitForExistence(timeout: timeout), "The share sheet did not open.")
            app.navigationBars["Downloads"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(shareTarget.waitForNonExistence(timeout: timeout), "The share sheet did not close.")
        }

        XCTContext.runActivity(named: "Preview the file") { _ in
            app.staticTexts[filename].tapWhenHittable(in: app)
            let preview = app.otherElements["QLPreviewControllerView"]
            XCTAssertTrue(preview.waitForExistence(timeout: timeout), "The PDF preview did not open.")
            app.buttons["Done"].firstMatch.tapWhenHittable(in: app)
            XCTAssertTrue(preview.waitForNonExistence(timeout: timeout))
        }

        XCTContext.runActivity(named: "Delete the file") { _ in
            app.staticTexts[filename].swipeLeft()
            app.buttons["Delete"].tapWhenHittable(in: app)
            XCTAssertTrue(app.staticTexts[filename].waitForNonExistence(timeout: timeout),
                          "The deleted file is still listed.")
        }
    }

    func testWhenARFileIsOpenedThenItIsPreviewedInQuickLook() throws {
        let site = try localWebsite()

        site.startDownload(.usdz, in: app)

        let preview = app.otherElements["QLPreviewControllerView"]
        XCTAssertTrue(preview.waitForExistence(timeout: timeout), "The AR file was not previewed.")
    }

    private func saveToDownloads() {
        let save = app.buttons["Save to Downloads"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout), "The Save to Downloads prompt did not appear.")
        save.tap()
    }

    private func openDownloads() {
        app.dismissAddressBarEditing()
        app.buttons["Browser.Toolbar.Button.Menu"].tapWhenHittable(in: app)
        let menu = app.descendants(matching: .any)["Browser.Menu.List"]
        let downloads = app.buttons["Downloads"]
        menu.swipeUpToReveal(downloads, timeout: timeout)
        downloads.tap()
        XCTAssertTrue(app.navigationBars["Downloads"].waitForExistence(timeout: timeout))
    }
}
