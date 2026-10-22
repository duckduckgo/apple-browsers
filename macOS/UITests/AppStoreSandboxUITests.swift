//
//  AppStoreSandboxUITests.swift
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

import SharedTestUtilities
import XCTest

/// App Store (sandboxed) build specific behaviour.
///
/// The sandboxed app can only access `~/Downloads` (`com.apple.security.files.downloads.read-write`)
/// and its own container on its own. Any other location is accessible only after the user grants it
/// in an Open/Save panel (`com.apple.security.files.user-selected.read-write`), and that grant survives
/// an app relaunch only through a persisted security-scoped bookmark:
/// - the custom downloads location is stored as a security-scoped bookmark (`DownloadsPreferences`);
/// - every download stores a security-scoped bookmark of its file (`DownloadListStore`).
///
/// These tests validate that the access is still there after relaunching the app.
class AppStoreSandboxUITests: UITestCase {

    private var webView: XCUIElement!
    private var popover: XCUIElement!
    private var table: XCUIElement!

    override func setUpWithError() throws {
        try super.setUpWithError()
        app = XCUIApplication.setUp()
        guard app.isSandboxed else {
            throw XCTSkip("App Store sandbox tests only run against the App Store build")
        }
        app.enforceSingleWindow()

        webView = app.webViews.firstMatch
        popover = app.popovers.containing(.table, identifier: "DownloadsViewController.table").firstMatch
        table = popover.tables["DownloadsViewController.table"]
        waitForNewTabPage()

        // Disable warn before quit to allow Cmd+Q to quit immediately on restart
        app.disableWarnBeforeQuitting()
    }

    override func tearDown() {
        webView = nil
        popover = nil
        table = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Test Cases

    /// A custom downloads location outside of the auto-granted folders is only accessible through
    /// the security-scoped bookmark persisted when the folder is selected. After relaunch the location
    /// must be restored (not reset to ~/Downloads) and downloads must still be saved into it
    /// without asking for a location.
    func testCustomDownloadsLocation_AccessPersistsAcrossRestart() throws {
        let customDir = try makeNonGrantedDirectory()
        configureDownloadPreferences(downloadsLocation: customDir)

        restartApp()

        // The location is reset to ~/Downloads when the persisted bookmark can't be resolved
        // or the folder isn't writable
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        XCTAssertEqual(selectedDownloadsLocationPath(), customDir.standardizedFileURL.path,
                       "Custom downloads location should be restored after restart")
        app.closePreferencesWindow()

        // Write access: the file should be saved into the custom folder without presenting a Save panel
        let fileName = "sandbox-location-\(UUID().uuidString).bin"
        trackDownloadForCleanup(fileName, in: customDir)
        startDownload(fileName: fileName)

        assertDownloadListed(filename: fileName)
        XCTAssertFalse(app.dialogs.containing(.button, identifier: "OKButton").firstMatch.exists,
                       "Download into the custom location should not ask where to save the file")
        waitForFile(at: customDir.appendingPathComponent(fileName), timeout: UITests.Timeouts.localTestServer)
    }

    /// A file downloaded into a non-granted folder is only accessible through its own security-scoped
    /// bookmark once the folder is no longer the downloads location. After relaunch the download must
    /// still be listed as an existing file and the file actions must be available.
    func testDownloadedFileInCustomLocation_AccessPersistsAcrossRestart() throws {
        let customDir = try makeNonGrantedDirectory()
        configureDownloadPreferences(downloadsLocation: customDir)

        let fileName = "sandbox-file-\(UUID().uuidString).bin"
        trackDownloadForCleanup(fileName, in: customDir)
        startDownload(fileName: fileName)
        assertDownloadListed(filename: fileName, sizeLabelRegex: "1.0 MB")
        waitForFile(at: customDir.appendingPathComponent(fileName), timeout: UITests.Timeouts.localTestServer)

        // Switch the downloads location back to ~/Downloads, so the folder access is no longer granted
        // by the downloads location bookmark and only the downloaded file bookmark is left.
        app.typeKey(.escape, modifierFlags: [])
        configureDownloadPreferences(downloadsLocation: downloadsDirectory)

        restartApp()

        // The download is dropped from the list when its file bookmark can't be resolved on launch
        assertDownloadListed(filename: fileName, sizeLabelRegex: "1.0 MB")
        let row = downloadRow(fileName: fileName)
        XCTAssertTrue(row.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertFalse(row.staticTexts["Removed"].exists, "Downloaded file should still be accessible after restart")

        // "Open" and "Show in Finder" are only shown when the app can see the downloaded file
        row.click()
        row.rightClick()
        // "Copy Download Link" is always shown, so it identifies the download context menu
        let copyLinkItem = NSPredicate.keyPath(\.title, equalTo: "Copy Download Link")
        let contextMenu = app.menus.containing(.menuItem, where: copyLinkItem).firstMatch
        XCTAssertTrue(contextMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Download context menu should open")
        XCTAssertTrue(contextMenu.menuItems.matching(\.title, equalTo: "Show in Finder").firstMatch.exists,
                      "Show in Finder should be available for an accessible downloaded file")
        XCTAssertTrue(contextMenu.menuItems.matching(\.title, equalTo: "Open").firstMatch.exists,
                      "Open should be available for an accessible downloaded file")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Helpers

    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Creates a folder in the home directory: not ~/Downloads and not the app container,
    /// so the sandboxed app can't access it unless the user selects it.
    private func makeNonGrantedDirectory() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("DDG-AppStoreSandboxUITests-\(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(dir.standardizedFileURL.path.hasPrefix(downloadsDirectory.standardizedFileURL.path))

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Files are deleted before directories, so the directory is removed once it is empty
        trackForCleanup(dir.path)
        return dir
    }

    private func trackDownloadForCleanup(_ fileName: String, in directory: URL) {
        trackForCleanup(directory.appendingPathComponent(fileName).path)
        trackForCleanup(directory.appendingPathComponent(fileName + ".duckload").path)
    }

    private func configureDownloadPreferences(downloadsLocation: URL) {
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        app.preferencesSetRestorePreviousSession(to: .newWindow, in: app.preferencesWindow)
        app.setOpenDownloadsPopupOnCompletion(enabled: true)
        app.setAlwaysAskWhereToSaveFiles(enabled: false)

        if selectedDownloadsLocationPath() != downloadsLocation.standardizedFileURL.path {
            app.setDownloadsLocation(to: downloadsLocation)
        }
        XCTAssertEqual(selectedDownloadsLocationPath(), downloadsLocation.standardizedFileURL.path)

        app.closePreferencesWindow()
    }

    private func selectedDownloadsLocationPath() -> String? {
        let pathControlId = "PreferencesGeneralView.downloadsLocation.pathControl"
        let pathControl = app.preferencesWindow.otherElements[pathControlId].firstMatch
        XCTAssertTrue(pathControl.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Downloads location path control should exist")
        guard let value = pathControl.value as? String else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.path
    }

    private func startDownload(fileName: String) {
        app.openNewTab()
        waitForNewTabPage()
        app.activateAddressBar()
        app.pasteURL(URL.testsDownload(size: "1MB", filename: fileName), pressingEnter: true)
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.navigation),
                      "Downloads popup should open on completion")
    }

    private func restartApp() {
        app.restart()
        _ = app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence)
        app.enforceSingleWindow()
        waitForNewTabPage()
    }

    private func waitForNewTabPage() {
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    private func openDownloadsPopup() {
        app.openDownloads()
        if !popover.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            app.openDownloads()
            XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        }
    }

    private func downloadRow(fileName: String) -> XCUIElement {
        table.cells.containing(NSPredicate(format: "label == %@ OR value == %@", fileName, fileName)).firstMatch
    }

    /// Opens the Downloads popover (if needed) and asserts the filename and, optionally, the size label exist.
    private func assertDownloadListed(filename: String, sizeLabelRegex: String? = nil) {
        if !popover.exists {
            openDownloadsPopup()
        }
        XCTAssertTrue(popover.staticTexts[filename].waitForExistence(timeout: UITests.Timeouts.localTestServer),
                      "\(filename) should be listed in Downloads")
        guard let sizeLabelRegex else { return }
        let sizeLabel = NSPredicate.keyPath(\.value, matchingRegex: sizeLabelRegex)
        let size = downloadRow(fileName: filename).staticTexts.matching(sizeLabel).firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: UITests.Timeouts.localTestServer),
                      "\(filename) should show its size")
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) {
        let predicate = NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected file to exist at \(url.path)")
    }

}
