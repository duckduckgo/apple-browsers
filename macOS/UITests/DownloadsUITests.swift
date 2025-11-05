//
//  DownloadsUITests.swift
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

import XCTest

class DownloadsUITests: UITestCase {

    private var webView: XCUIElement!
    private var popover: XCUIElement!
    private var table: XCUIElement!
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()

        webView = app.webViews.firstMatch
        popover = app.popovers.containing(.table, identifier: "DownloadsViewController.table").firstMatch
        table = popover.tables["DownloadsViewController.table"]
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    override func tearDown() {
        webView = nil
        popover = nil
        app = nil
        super.tearDown()
    }

    // MARK: - Test Cases

    /// Verifies that a completed download triggers the Downloads UI when auto-open is enabled.
    func testDownloadFinishesThenPopupIsShown() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        downloadFile()
        verifyDownloadPopupIsShown()
    }

    /// Ensures clearing downloads empties the list and the UI reflects an empty state.
    func testClearDownloadsRemovesFiles() {
        // Disable "Always ask" and enable auto-open downloads popup
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        downloadFile()
        // Ensure the Downloads popover is visible
        verifyDownloadPopupIsShown()
        clearDownloads()
        verifyNoRecentDownloads()
    }

    /// Confirms that enabling "Always ask where to save files" shows the system save panel.
    func testAskWhereToSaveFilesShowsPrompt() {
        // Enable in-app preference: Always ask where to save files
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)

        // Trigger a download that should prompt for a save location (Content-Disposition: attachment)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        let attachmentURL = URL.testsDownload(size: "5MB").absoluteString
        openSiteForDownloadingFile(url: attachmentURL)

        // Expect NSSavePanel as a sheet
        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.navigation), "Save panel should appear when 'Always ask' is enabled")

        // Dismiss the sheet to clean up
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        cancel.click()
    }

    /// Closing a Fire window with an in‑progress download should present a warning
    func testFireWindowWithInProgressDownloadShowsWarning() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        app.enforceSingleWindow()
        app.openFireWindow()

        downloadLargeFile(onFireWindow: true)
        // Wait for the download to actually start (Downloads button becomes available)
        let downloadsButton = app.buttons["NavigationBarViewController.downloadsButton"]
        _ = downloadsButton.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        assertDownloadListed(filenameRegex: ".MMA.+10GB.*", timeout: UITests.Timeouts.navigation)
        app.typeKey(.escape, modifierFlags: [])

        // Attempt to close window → expect warning
        app.closeWindow()
        verifyDownloadInProgressWarning()
        // Cancel the warning and ensure download still present
        let sheet = app.sheets.firstMatch
        sheet.buttons["Don’t Close"].click()

        // Verify download is in progress and present
        assertDownloadListed(filenameRegex: ".MMA.+10GB.*", sizeLabelRegex: ".* of .*( – .*|)", timeout: UITests.Timeouts.elementExistence)
        app.typeKey(.escape, modifierFlags: [])

        // Try closing again and accept the warning to stop download
        app.closeWindow()
        verifyDownloadInProgressWarning()

        sheet.buttons["Close"].click()

        // Reopen main window and verify download was cancelled
        app.enforceSingleWindow()
        // Verify no downloads are in the main window
        verifyNoRecentDownloads()
    }

    /// Starts a larger download and verifies progress by asserting the Stop action is available in the context menu.
    func testDownloadProgress_ShowsDownloadsButtonAndContents() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        // Start a larger download to ensure progress/UI tracking
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        downloadLargeFile()

        // Open Downloads popover and assert it's visible
        assertDownloadListed(filenameRegex: ".MMA.+10GB.*", sizeLabelRegex: ".* of .*( – .*|)", timeout: UITests.Timeouts.navigation)
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        firstRow.click()
        firstRow.rightClick()
        let stopItem = app.menuItems.containing(\.title, equalTo: "Stop")
            .firstMatch
        XCTAssertTrue(stopItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Additionally assert progress text and filename
        assertDownloadListed(sizeLabelRegex: ".* of .*( – .*|)")
    }

    /// Triggers two distinct downloads and verifies the Downloads UI is available for multiple items.
    func testMultipleDownloads_AppearInList() {
        // Trigger two distinct downloads via Content-Disposition headers
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        let baseName = "same-name-\(UUID().uuidString).bin"
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

        // Track both completed downloads (original and " 1.bin" suffix)
        trackForCleanup(downloadsDir.appendingPathComponent(baseName).path)
        trackForCleanup(downloadsDir.appendingPathComponent(baseName.replacingOccurrences(of: ".bin", with: " 1.bin")).path)

        openSiteForDownloadingFile(url: URL.testsDownload(size: "1MB", filename: baseName).absoluteString)
        // Briefly allow processing of the first trigger
        _ = app.windows.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence)

        openSiteForDownloadingFile(url: URL.testsDownload(size: "1MB", filename: baseName).absoluteString)

        // Downloads popover should open and assert two download rows are present
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.navigation))

        XCTAssertTrue(table.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(table.cells.wait(for: \.count, in: 2..., timeout: UITests.Timeouts.localTestServer), "Should have at least 2 cells in downloads table")
        assertDownloadListed(filename: baseName)
        assertDownloadListed(filename: baseName.replacingOccurrences(of: ".bin", with: " 1.bin"))
    }

    /// When using the save panel, a custom filename should be saved and displayed in the Downloads popover.
    func testSavePanel_UniqueFilename_SavedAndListed() {
        // Enable save panel behavior and clear existing downloads
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)

        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        // Trigger a small download that will show the save panel
        openSiteForDownloadingFile(url: URL.testsDownload(size: "1MB").absoluteString)

        let uniqueName = "ui-" + UUID().uuidString + ".bin"
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent("ddg-uitests-downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        trackForCleanup(targetDir.path)
        saveFileAs(uniqueName, in: targetDir)

        XCTAssertTrue(popover.waitForExistence(timeout: 15))
        assertDownloadListed(filename: uniqueName)

        // Verify file exists at chosen directory
        waitForFile(at: targetDir.appendingPathComponent(uniqueName), timeout: UITests.Timeouts.localTestServer)
    }

    /// Cancelling the save dialog should cancel the download and leave the list empty.
    func testDownloadCancellation_SaveDialogCancelled_ShowsEmpty() {
        // Enable "Always ask"
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        openSiteForDownloadingFile(url: URL.testsDownload(size: "5GB").absoluteString)

        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Save dialog should appear for attachment")

        // Cancel the dialog to cancel download
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        cancel.click()

        // Verify no downloads were recorded
        verifyNoRecentDownloads()
    }

    /// When save panel is shown and a location is chosen, the file is saved there.
    func testSavePanel_SavesToSelectedLocation_CreatesFile() throws {
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)

        app.openNewTab()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        // Trigger a small download that will show the save panel
        openSiteForDownloadingFile(url: URL.testsDownload(size: "1MB").absoluteString)

        // Before saving, verify suggested filename matches the download name (1MB.bin)
        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let filenameField = saveSheet.textFields.firstMatch
        XCTAssertTrue(filenameField.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let initialName = filenameField.value as? String
        XCTAssertTrue(initialName == "1MB.bin" || initialName == "1MB", "Unexpected initial filename: \"\(initialName ?? "")\" not equal to \"1MB.bin\"")

        let uniqueName = "ui-" + UUID().uuidString + ".bin"
        XCTAssertNotEqual(initialName, uniqueName)
        let targetDir = FileManager.default.temporaryDirectory.appendingPathComponent("ddg-uitests-downloads-2", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        trackForCleanup(targetDir.path)
        saveFileAs(uniqueName, in: targetDir)
        waitForFile(at: targetDir.appendingPathComponent(uniqueName), timeout: UITests.Timeouts.localTestServer)
    }

    /// Navigating to unrenderable content (no attachment disposition) should still start a download.
    func testUnrenderableMimeType_Navigated_TriggersDownload() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)

        // Simulate navigating to a page that has binary content with an unrenderable MIME type
        let uniqueName = "inline-binary-\(UUID().uuidString).bin"
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        trackForCleanup(downloadsDir.appendingPathComponent(uniqueName).path)

        let binaryData = "Some binary content".data(using: .utf8)!
        let url = URL.testsServer.appendingPathComponent(uniqueName).appendingTestParameters(
            data: binaryData,
            headers: ["Content-Type": "application/x-weird-binary"]
        )

        app.openNewTab()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.pasteURL(url, pressingEnter: true)

        XCTAssertTrue(popover.waitForExistence(timeout: 15))
        assertDownloadListed(filename: uniqueName)
    }

    /// Restoring windows/tabs after app restart should not re-trigger a past download.
    func testTabRestoration_DoesNotRestartDownloadOnAppRestart() {
        // Configure once up front with restore enabled
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false,
                                     restorePreviousSession: true)

        app.openNewTab()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        triggerDownloadWithUniqueName(size: "1MB")

        // Expect exactly one item + "Open Downloads folder"
        XCTAssertTrue(table.cells.wait(for: \.count, equals: 2, timeout: UITests.Timeouts.localTestServer), "Should have exactly 2 cells (1 download + Open Downloads folder), actual: \(table.cells.count)")

        // Quit and relaunch
        app.typeKey("q", modifierFlags: [.command])
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence)
        app.enforceSingleWindow()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Verify count did not increase
        openDownloadsPopup()
        XCTAssertTrue(table.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(table.cells.count, 2)
    }

    /// Restoring a page where JS triggers a download after 500ms must NOT start the download again on restoration.
    func testTabRestoration_JSDelayedDownload_DoesNotReTrigger() {
        // Configure once with restore enabled; avoid duplicate preference writes
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false,
                                     restorePreviousSession: true)

        app.openNewTab()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        // Page that schedules a delayed download via JS timer to a unique file
        let uniqueName = "delayed-\(UUID().uuidString).bin"
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        trackForCleanup(downloadsDir.appendingPathComponent(uniqueName).path)

        let delayedURL = URL.testsDownload(size: "1MB", filename: uniqueName).absoluteString
        let pageHTML = """
        <html><head><title>Delayed DL</title></head>
        <body>
          <script>
            setTimeout(function(){ window.location.href = '\(delayedURL.escapedJavaScriptString())'; }, 500);
          </script>
          Page loaded!
        </body></html>
        """
        let url = URL.testsServer.appendingTestParameters(data: pageHTML.utf8data)

        // Already configured above with restorePreviousSession = true
        openSiteForDownloadingFile(url: url.absoluteString)

        // Wait for the delayed download to start and appear
        XCTAssertTrue(popover.waitForExistence(timeout: 15))

        // We don't depend on exact name; ensure at least one item appears

        XCTAssertTrue(table.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Expect exactly one item + "Open Downloads folder"
        XCTAssertTrue(table.cells.wait(for: \.count, equals: 2, timeout: UITests.Timeouts.localTestServer), "Should have exactly 2 cells (1 download + Open Downloads folder), actual: \(table.cells.count)")

        // Quit and relaunch to restore session
        app.typeKey("q", modifierFlags: [.command])
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence)

        XCTAssertTrue(webView.staticTexts["Page loaded!"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        sleep(2)

        // Verify no NEW download was added after restoration (still exactly one)
        openDownloadsPopup()
        XCTAssertTrue(table.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertEqual(table.cells.count, 2)
    }

    /// Reopening a closed tab (Cmd+Shift+T) should not re-trigger the download for that page.
    func testReopenClosedTab_DoesNotRestartDownload() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)

        app.openNewTab()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        app.openNewTab()
        triggerDownloadWithUniqueName(size: "1MB")

        // Assert a single item exists

        // Expect exactly one item + "Open Downloads folder"
        XCTAssertTrue(table.cells.wait(for: \.count, equals: 2, timeout: UITests.Timeouts.localTestServer), "Should have exactly 2 cells (1 download + Open Downloads folder)")

        // Close the current tab and immediately reopen last closed tab
        app.closeCurrentTab()
        app.typeKey("t", modifierFlags: [.command, .shift])

        // Wait a short moment for potential retrigger (should not happen)
        openDownloadsPopup()
        _ = table.waitForExistence(timeout: UITests.Timeouts.elementExistence)
        XCTAssertEqual(table.cells.count, 2)
    }

    /// Option+click should download an HTML link instead of opening it.
    func testOptionClick_DownloadsLinkedHTMLFile() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)

        // Linked HTML target
        let uniqueLinkedName = "linked-\(UUID().uuidString).html"
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        trackForCleanup(downloadsDir.appendingPathComponent(uniqueLinkedName).path)

        let linkedURL = URL.testsDownload(size: "1KB", filename: uniqueLinkedName)

        // Page containing the link
        let pageHTML = """
        <html>
          <head><title>Link Host</title></head>
          <body>
            <a id="html-link" href="\(linkedURL.absoluteString.escapedJavaScriptString())">HTML Link</a>
          </body>
        </html>
        """
        let pageURL = URL.testsServer.appendingTestParameters(data: pageHTML.utf8data)

        app.openNewTab()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.pasteURL(pageURL, pressingEnter: true)

        let link = app.webViews.firstMatch.links["HTML Link"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCUIApplication.perform(withKeyModifiers: [.option]) {
            link.click()
        }

        // The saved name should derive from the target lastPathComponent
        assertDownloadListed(filename: uniqueLinkedName)
    }

    /// Custom downloads location: set to a temp folder and verify completed files are saved there
    func testCustomDownloadsLocation_FilesGoIntoSelectedDirectory() {
        // Set a custom target directory using the unified helper
        let customDir = FileManager.default.temporaryDirectory.appendingPathComponent("ddg-custom-downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        trackForCleanup(customDir.path)
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false,
                                     restorePreviousSession: false,
                                     downloadsLocation: customDir)

        // Start a download and verify it lands in the customDir
        app.openNewTab()
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let unique = UUID().uuidString
        let url = URL.testsDownload(size: "1MB", filename: "custom-dir-file-\(unique).bin")
        app.pasteURL(url, pressingEnter: true)

        // Wait for completion in downloads UI
        XCTAssertTrue(popover.waitForExistence(timeout: 15.0))
        assertDownloadListed(filename: "custom-dir-file-\(unique).bin")

        // Verify exists in customDir
        let expected = customDir.appendingPathComponent("custom-dir-file-\(unique).bin")
        waitForFile(at: expected, timeout: UITests.Timeouts.localTestServer)
    }

    /// Window close during a long download should not destabilize the browser; Downloads UI remains accessible.
    func testWindowCloseDuringDownload_BrowserStable() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        // Start a long download
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        // Track both the final and in-progress files
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let filename = "5GB.bin"
        trackForCleanup(downloadsDir.appendingPathComponent(filename).path)
        trackForCleanup(downloadsDir.appendingPathComponent(filename + ".duckload").path)

        openSiteForDownloadingFile(url: URL.testsDownload(size: "5GB").absoluteString)
        assertDownloadListed(filename: "5GB.bin")

        // Immediately close window and open a new one; browser should remain stable
        app.closeWindow()
        app.openNewWindow()
        XCTAssertTrue(app.exists, "Browser should remain functional after window close during download")

        // Downloads UI should still be accessible
        openDownloadsPopup()
        verifyDownloadPopupIsShown()
        assertDownloadListed(filename: "5GB.bin", sizeLabelRegex: ".*(KB|MB|GB).*")
    }

    /// JS‑initiated data: URL download should surface the save panel when "Always ask" is enabled.
    func testJavaScriptGeneratedDownload_DataURL() throws {
        // Generate a download via data: URL on a served page
        let pageHTML = """
        <html>
        <head><title>JS Data URL Download</title></head>
        <body>
          <a id="dl" href="data:application/octet-stream;charset=utf-8,hello-world" download="hello-data.txt">Download via Data URL</a>
        </body>
        </html>
        """
        let url = URL.testsServer.appendingTestParameters(data: pageHTML.utf8data)
        // Enable "Always ask"
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        openSiteForDownloadingFile(url: url.absoluteString)

        let link = webView.links["Download via Data URL"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        link.tap()
        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        cancel.click()
    }

    /// JS‑initiated Blob download should surface the save panel when "Always ask" is enabled.
    func testJavaScriptGeneratedDownload_Blob() throws {
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        // Generate a download via Blob on a served page
        let pageHTML = """
        <html>
        <head><title>JS Blob Download</title></head>
        <body>
          <script>
            function doDownload(){
              var blob = new Blob(['blob-content'], {type: 'application/octet-stream'});
              var link = document.createElement('a');
              link.href = URL.createObjectURL(blob);
              link.download = 'hello-blob.bin';
              document.body.appendChild(link);
              link.click();
            }
          </script>
          <a id="blob" href="#" onclick="doDownload(); return false;">Download via Blob</a>
        </body>
        </html>
        """
        let url = URL.testsServer.appendingTestParameters(data: pageHTML.utf8data)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        app.pasteURL(url, pressingEnter: true)
        let link = webView.links["Download via Blob"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        link.tap()
        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        cancel.click()
    }

    /// After a completed download, the Downloads list should persist across app restart.
    func testDownloadsPersistAcrossAppRestart() throws {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        // Complete a small download with a distinct name
        let fileName = "persist-test-1mb-\(UUID().uuidString).bin"
        let url = URL.testsDownload(size: "1MB", filename: fileName)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        // Track both the final and in-progress files
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        trackForCleanup(downloadsDir.appendingPathComponent(fileName).path)
        trackForCleanup(downloadsDir.appendingPathComponent(fileName + ".duckload").path)

        openSiteForDownloadingFile(url: url.absoluteString)
        XCTAssertTrue(popover.waitForExistence(timeout: 15.0))
        assertDownloadListed(filename: fileName, sizeLabelRegex: "1.0 MB")

        // Restart app and verify the same file is listed
        app.typeKey("q", modifierFlags: [.command])

        app.launch()
        _=app.wait(for: .runningForeground, timeout: UITests.Timeouts.elementExistence)
        app.enforceSingleWindow()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        openDownloadsPopup()
        assertDownloadListed(filename: fileName, sizeLabelRegex: "1.0 MB")
    }

    /// Quitting while a download is active should show a confirmation alert that can be cancelled.
    func testQuitAppWithActiveDownloads() throws {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        // Start a long download and attempt to quit; expect a sheet and cancel it
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        downloadLargeFile()
        // Ensure download actually started before quitting
        let downloadsButton = app.buttons["NavigationBarViewController.downloadsButton"]
        XCTAssertTrue(downloadsButton.waitForExistence(timeout: UITests.Timeouts.navigation))
        assertDownloadListed(filenameRegex: ".MMA.+10GB.*")

        app.typeKey("q", modifierFlags: [.command])
        let quitSheet = app.dialogs.firstMatch
        XCTAssertTrue(quitSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Quit confirmation sheet should appear with active downloads")

        let alertTitle = app.staticTexts["A download is in progress."]
        XCTAssertTrue(alertTitle.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Quit confirmation alert should appear with active downloads")
        // Button title uses a typographic apostrophe on macOS – match exact title deterministically
        let dontQuit = app.buttons["Don’t Quit"].firstMatch
        XCTAssertTrue(dontQuit.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        dontQuit.click()

        // Validate download is still running (Stop item visible in context menu)
        if !popover.exists {
            openDownloadsPopup()
        }

        XCTAssertTrue(table.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        firstRow.click()
        firstRow.rightClick()
        let stopItem = app.menuItems.containing(\.title, equalTo: "Stop")
        XCTAssertTrue(stopItem.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeKey(.escape, modifierFlags: [])

        // Now quit for real and validate app terminates
        app.typeKey("q", modifierFlags: [.command])
        let quitButton = app.buttons["Quit"].firstMatch
        XCTAssertTrue(quitButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        quitButton.click()
        // App should no longer be running in the foreground shortly after
        XCTAssertTrue(app.wait(for: .notRunning, timeout: UITests.Timeouts.elementExistence))
    }

    /// Opening a download in a background tab with "Always ask where to save files" enabled,
    /// then closing that background tab, must not add any download entry.
    func testDownloadCancellation_TabClose_CancelsDownload() throws {
        // Ensure a clean state and, in a single settings pass, enable:
        // - Always ask where to save files (to surface save sheet)
        // - Keep new tabs in background (do NOT switch to newly opened tab)
        clearAllDownloadsIfPresent()
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)

        // Prepare a popup page on the local server which sets a clear title, then navigates to a binary to trigger download
        let downloadURL = URL.testsDownload(size: "10MB").absoluteString
        let popupHTML = """
        <html>
          <head><title>Background Download</title></head>
        <body>
            <script>
              setTimeout(function(){ window.location.href = '\(downloadURL.escapedJavaScriptString())'; }, 50);
            </script>
        </body>
        </html>
        """
        let popupURL = URL.testsServer.appendingTestParameters(data: popupHTML.utf8data)

        // Launcher page opens the popup (new tab) and confirms via JS that it started
        let launcherHTML = """
        <html>
          <head>
            <title>Launcher</title>
            <script>
              function openPopup(){
                var w = window.open('\(popupURL.absoluteString.escapedJavaScriptString())', '_blank');
                if (w) {
                  document.title = 'Download started';
                  var s = document.getElementById('status');
                  if (s) { s.textContent = 'Download started'; }
                  setTimeout(function(){ window.focus(); }, 100);
                } else {
                  document.title = 'Popup blocked';
                }
              }
            </script>
          </head>
          <body>
            <a id="open" href="#" onclick="openPopup(); return false;">Open Popup</a>
            <div id="status"></div>
          </body>
        </html>
        """
        let launcherURL = URL.testsServer.appendingTestParameters(data: launcherHTML.utf8data)

        // Load launcher and trigger popup (new background tab)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        app.pasteURL(launcherURL, pressingEnter: true)
        let openLink = app.webViews.firstMatch.links["Open Popup"]
        XCTAssertTrue(openLink.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Open link in a new tab with ⌘+click
        XCUIApplication.perform(withKeyModifiers: [.command]) {
            openLink.click()
        }

        // Validate via JS-updated DOM that download was initiated from launcher tab
        let startedIndicator = app.webViews.firstMatch.staticTexts
            .containing(\.value, containing: "Download started")
            .firstMatch
        XCTAssertTrue(startedIndicator.waitForExistence(timeout: UITests.Timeouts.localTestServer))

        // Close the popup tab with the "x" button
        let tabGroup = app.windows.firstMatch
            .tabGroups["Tabs"]
        let popupTab = tabGroup
            .radioButtons
            .containing(\.title, equalTo: "Background Download")
            .firstMatch
        XCTAssertTrue(popupTab.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        try popupTab.closeTab()

        // Verify no download was added
        verifyNoRecentDownloads()
    }

    /// From the Downloads popover, "Show in Finder" should work and an item can be removed individually.
    func testFileActions_ShowInFinder_And_RemoveIndividual() throws {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        // Ensure a clean state then complete a small download to have a row
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        clearAllDownloadsIfPresent()

        // Track both the final and in-progress files
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let filename = "1MB.bin"
        trackForCleanup(downloadsDir.appendingPathComponent(filename).path)
        trackForCleanup(downloadsDir.appendingPathComponent(filename + ".duckload").path)

        openSiteForDownloadingFile(url: URL.testsDownload(size: "1MB").absoluteString)
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.navigation))

        // Wait until a completed row (size text) appears, then right-click that row
        assertDownloadListed(filenameRegex: "1MB.*", sizeLabelRegex: "1.0 MB")

        XCTAssertTrue(table.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        firstRow.click()
        firstRow.rightClick()
        let showInFinder = app.menuItems.containing(\.title, containing: "Show in Finder")
        XCTAssertTrue(showInFinder.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        showInFinder.firstMatch.click()

        openDownloadsPopup()
        XCTAssertTrue(table.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(firstRow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        firstRow.click()
        firstRow.rightClick()
        let removeItem = app.menuItems.containing(\.title, containing: "Remove from List")
        XCTAssertTrue(removeItem.firstMatch.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        removeItem.firstMatch.click()

        // Verify popover shows empty state without toggling it closed
        verifyNoRecentDownloads()
    }

    /// Clicking a link that opens a download in a new tab should auto‑close the extra tab after triggering.
    func testTabManagement_DownloadTabAutoCloses_AfterOpen() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        let filename = "auto-tab-close-\(UUID().uuidString).bin"
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        trackForCleanup(downloadsDir.appendingPathComponent(filename).path)

        let downloadURL = URL.testsDownload(size: "1MB", filename: filename).absoluteString
        let pageHTML = """
        <html>
          <head><title>Auto Open Via Click</title></head>
          <body>
            <a id="dl" href="\(downloadURL.escapedJavaScriptString())" target="_blank">Open Download</a>
          </body>
        </html>
        """
        let url = URL.testsServer.appendingTestParameters(data: pageHTML.utf8data)

        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        app.pasteURL(url, pressingEnter: true)
        let link = app.webViews.firstMatch.links["Open Download"]
        XCTAssertTrue(link.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Click to open in new tab (respects default behavior of target=_blank)
        link.click()

        // Downloads UI should be accessible
        verifyDownloadPopupIsShown()
        // At the end, only one tab should remain
        let tabsGroup = app.windows.firstMatch.tabGroups["Tabs"]
        XCTAssertEqual(tabsGroup.radioButtons.count, 1)
    }

    /// Cancelling a long download should expose a "Restart Download" action that is clickable.
    func testRetry_CanceledLongDownload_ShowsRestartAndActionClickable() throws {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        // Start a long download
        downloadLargeFile()
        // Open downloads and cancel the first row
        assertDownloadListed(filenameRegex: ".MMA.+10GB.*", sizeLabelRegex: ".* of .*( – .*|)", timeout: UITests.Timeouts.navigation)

        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        firstRow.click()
        // Right-click and choose Stop to cancel
        firstRow.rightClick()
        let stopItem = popover.menuItems.containing(\.title, equalTo: "Stop").firstMatch
        XCTAssertTrue(stopItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        stopItem.click()

        // Now right-click again and click Restart Download
        firstRow.rightClick()
        let restartItem = popover.menuItems.containing(\.title, equalTo: "Restart Download").firstMatch
        XCTAssertTrue(restartItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        restartItem.click()

        // Assert popover remains open (do not toggle with Cmd+J)
        // Progress should resume: right-click again and ensure the Stop action is available
        firstRow.rightClick()
        XCTAssertTrue(stopItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Two links on a served page should yield two download entries; Downloads UI must be accessible.
    func testMultipleDownloads_FromServedPage_ShowsTwoItems() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        // Create unique filenames for both downloads
                let fileNameA = "file-a-\(UUID().uuidString).bin"
        let fileNameB = "file-b-\(UUID().uuidString).bin"

        // Track files in default downloads directory
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        trackForCleanup(downloadsDir.appendingPathComponent(fileNameA).path)
        trackForCleanup(downloadsDir.appendingPathComponent(fileNameB).path)

        // Page with two direct download links
        let pageHTML = """
        <html><head><title>Two Downloads</title></head>
        <body>
          <a href="\(URL.testsDownload(size: "1MB", filename: fileNameA).absoluteString)">File A</a>
          <a href="\(URL.testsDownload(size: "5MB", filename: fileNameB).absoluteString)">File B</a>
        </body></html>
        """
        let url = URL.testsServer.appendingTestParameters(data: pageHTML.utf8data)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearAllDownloadsIfPresent()

        openSiteForDownloadingFile(url: url.absoluteString)
        let linkA = webView.links["File A"].firstMatch
        let linkB = webView.links["File B"].firstMatch
        XCTAssertTrue(linkA.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(linkB.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        linkA.tap()
        linkB.tap()

        // Verify both files appear with correct sizes
        assertDownloadListed(filename: fileNameA, sizeLabelRegex: "1.0 MB")
        assertDownloadListed(filename: fileNameB, sizeLabelRegex: "5.0 MB")
    }

    // MARK: - Helper Methods

    private func downloadFile(onFireWindow: Bool = false) {
        app.openNewTab()
        // wait for the New Tab page to load
        if onFireWindow {
            XCTAssertTrue(app.staticTexts["Fire Window"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        } else {
            XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        }

        for filename in ["1MB.bin", "1MB 1.bin", "1MB 2.bin"] {
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let finalPath = downloadsDir.appendingPathComponent(filename).path
            trackForCleanup(finalPath)
        }
        // Use a small ZIP so WebKit downloads it (not rendered inline)
        openSiteForDownloadingFile(url: URL.testsDownload(size: "1MB").absoluteString)
    }

    private func downloadLargeFile(onFireWindow: Bool = false) {
        app.openNewTab()
        // wait for the New Tab page to load
        if onFireWindow {
            XCTAssertTrue(app.staticTexts["Fire Window"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        } else {
            XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        }

        // Larger file to keep download in-progress reliably
        let url = "https://mmatechnical.com/Download/Download-Test-File/(MMA)-10GB.zip"
        openSiteForDownloadingFile(url: url)

        // Track both the final file and the temporary .duckload file
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let filename = url.components(separatedBy: "/").last ?? "(MMA)-10GB.zip"
        let finalPath = downloadsDir.appendingPathComponent(filename).path
        let tempPath = downloadsDir.appendingPathComponent(filename + ".duckload").path
        trackForCleanup(finalPath)
        trackForCleanup(tempPath)
    }

    private func openSiteForDownloadingFile(url: String) {
        app.activateAddressBar()
        app.pasteURL(URL(string: url)!, pressingEnter: true)
    }

    /// Save panel variant that first navigates to a target directory using Go To Folder, then saves
    private func saveFileAs(_ fileName: String, in directoryURL: URL) {
        app.setSaveDialogLocation(to: directoryURL)
        app.enterSaveDialogFileNameAndConfirm(fileName)

        // Track the saved file for cleanup
        let filePath = directoryURL.appendingPathComponent(fileName).path
        trackForCleanup(filePath)
    }

    private func verifyDownloadPopupIsShown() {
        let clearButton = popover.buttons["DownloadsViewController.clearDownloadsButton"]

        XCTAssertTrue(clearButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Downloads popover should be visible after Cmd+J")
    }

    /// Builds a tests-server download URL with desired filename and size.
    private func makeDownloadURL(filename: String, size: String = "1MB") -> URL {
        URL.testsDownload(size: size, filename: filename)
    }

    /// Triggers a download for given size and optional filename (generates UUID-based when not provided).
    /// Returns the filename used.
    @discardableResult
    private func triggerDownloadWithUniqueName(size: String = "1MB", filename: String? = nil) -> String {
        let usedName = filename ?? ("ui-" + UUID().uuidString + ".bin")
        let url = makeDownloadURL(filename: usedName, size: size)
        openSiteForDownloadingFile(url: url.absoluteString)

        // Track both the final file and the temporary .duckload file
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let finalPath = downloadsDir.appendingPathComponent(usedName).path
        let tempPath = downloadsDir.appendingPathComponent(usedName + ".duckload").path
        trackForCleanup(finalPath)
        trackForCleanup(tempPath)

        return usedName
    }

    /// Opens the Downloads popover (if needed) and asserts both size label (optional) and filename exist.
    private func assertDownloadListed(filename: String? = nil, filenameRegex: String? = nil, sizeLabelRegex: String? = nil, timeout: TimeInterval = UITests.Timeouts.localTestServer) {
        if !popover.exists {
            openDownloadsPopup()
        }
        if let sizeRegex = sizeLabelRegex {
            let size = popover.staticTexts.matching(.keyPath(\.value, matchingRegex: sizeRegex)).firstMatch
            XCTAssertTrue(size.waitForExistence(timeout: timeout))
        }
        if let filename {
            XCTAssertTrue(popover.staticTexts[filename].waitForExistence(timeout: timeout))
        }
        if let filenameRegex {
            let nameLabel = popover.staticTexts.matching(.keyPath(\.value, matchingRegex: filenameRegex)).firstMatch
            XCTAssertTrue(nameLabel.waitForExistence(timeout: timeout))
        }
    }

    private func clearDownloads() {
        let clearButton = app.buttons["DownloadsViewController.clearDownloadsButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Clear button should exist when downloads are present")
        clearButton.click()
        app.typeKey(.escape, modifierFlags: [])
    }

    private func clearAllDownloadsIfPresent() {
        if !popover.exists {
            openDownloadsPopup()
        }
        let clearButton = popover.buttons["DownloadsViewController.clearDownloadsButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        clearButton.click()
        verifyNoRecentDownloads()
        app.typeKey(.escape, modifierFlags: [])
    }

    private func verifyNoRecentDownloads() {
        // Ensure popover is open; if not, open it. Avoid toggling an already open popover.
        if !popover.exists {
            openDownloadsPopup()
        }
        XCTAssertTrue(popover.staticTexts["No recent downloads"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    private func verifyDownloadInProgressWarning() {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Closing Fire window with in-progress download should present a confirmation sheet")
    }

    private func openDownloadsPopup() {
        app.openDownloads()
        if !popover.waitForExistence(timeout: UITests.Timeouts.elementExistence) {
            app.openDownloads()
            XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        }
    }

    // Unified preferences configuration for Downloads tests
    private func configureDownloadPreferences(alwaysAskWhereToSave: Bool,
                                              openDownloadsPopupOnCompletion: Bool,
                                              switchToNewTabWhenOpened: Bool,
                                              restorePreviousSession: Bool = false,
                                              downloadsLocation: URL? = nil) {
        app.openPreferencesWindow()
        let prefs = app.preferencesWindow

        app.preferencesGoToGeneralPane()
        app.preferencesSetRestorePreviousSession(to: restorePreviousSession ? .restoreLastSession : .newWindow, in: prefs)
        app.setSwitchToNewTabWhenOpened(enabled: switchToNewTabWhenOpened)
        app.setOpenDownloadsPopupOnCompletion(enabled: openDownloadsPopupOnCompletion)
        app.setAlwaysAskWhereToSaveFiles(enabled: alwaysAskWhereToSave)

        if !alwaysAskWhereToSave {
            // Verify NSPathControl shows the correct location by inspecting the control and last item
            let pathControl = prefs.otherElements["PreferencesGeneralView.downloadsLocation.pathControl"].firstMatch
            XCTAssertTrue(pathControl.exists, "Downloads location path control should exist")

            var selectedPath: String? {
                guard let value = pathControl.value as? String else { return nil }
                let fileURL = URL(fileURLWithPath: value)
                let standardizedPath = fileURL.standardizedFileURL.path
                return standardizedPath
            }

            let desiredDir = downloadsLocation ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            if selectedPath != desiredDir.standardizedFileURL.path {
                app.setDownloadsLocation(to: desiredDir)
                // Track custom downloads directory for cleanup
                trackForCleanup(desiredDir.path)
            }

            XCTAssertEqual(selectedPath, desiredDir.standardizedFileURL.path)
        }

        app.closePreferencesWindow()
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) {
        let expectation = expectation(description: "File exists at path")
        let start = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: url.path) {
                expectation.fulfill()
                timer.invalidate()
                return
            }
            if Date().timeIntervalSince(start) > timeout {
                timer.invalidate()
            }
        }
        RunLoop.current.add(timer, forMode: .default)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout + 1.0)
        XCTAssertEqual(result, .completed, "Expected file to exist at \(url.path)")
    }

}
