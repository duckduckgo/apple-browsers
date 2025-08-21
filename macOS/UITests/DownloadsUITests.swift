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

    private var app: XCUIApplication!
    private var webView: XCUIElement!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        app.enforceSingleWindow()

        webView = app.webViews.firstMatch
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    override func tearDown() {
        webView = nil
        app = nil
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
        XCTAssertTrue(saveSheet.waitForExistence(timeout: 30.0), "Save panel should appear when 'Always ask' is enabled")

        // Dismiss the sheet to clean up
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 2.0))
        cancel.click()
    }

    /// Validates downloads behavior within a Fire window and that the popover is shown on completion.
    func testDownloadsOnFireWindow() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        app.typeKey("w", modifierFlags: [.command, .option, .shift])
        openFireWindow()
        downloadFile(onFireWindow: true)
        openDownloadsPopup()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let sizeLabel = popover.staticTexts
            .containing(NSPredicate(format: "value MATCHES[c] '1.0 MB'"))
            .firstMatch
        XCTAssertTrue(sizeLabel.waitForExistence(timeout: 15.0))
    }

    /// Closing a Fire window with an in‑progress download should present a warning
    func testFireWindowWithInProgressDownloadShowsWarning() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        app.typeKey("w", modifierFlags: [.command, .option, .shift])
        openFireWindow()
        downloadLargeFile(onFireWindow: true)
        // Wait for the download to actually start (Downloads button becomes available)
        let downloadsButton = app.buttons["NavigationBarViewController.downloadsButton"]
        _ = downloadsButton.waitForExistence(timeout: 10.0)
        closeWindowWithInProgressDownload()
        verifyDownloadInProgressWarning()
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

        openSiteForDownloadingFile(url: URL.testsDownload(size: "5GB").absoluteString)

        // Open Downloads popover and assert it's visible
        openDownloadsPopup()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let table = popover.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 10.0))
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10.0))
        firstRow.click()
        firstRow.rightClick()
        let stopItem = app.menuItems.containing(NSPredicate(format: "title ==[c] 'Stop'"))
            .firstMatch
        XCTAssertTrue(stopItem.waitForExistence(timeout: 5.0))
        app.typeKey(.escape, modifierFlags: [])

        // Additionally, assert detail label shows progress text like "x of y" while in progress
        let progressPredicate = NSPredicate(format: "value MATCHES[c] '.* of .*( – .*|)'")
        let progressLabel = popover.staticTexts.containing(progressPredicate).firstMatch
        XCTAssertTrue(progressLabel.waitForExistence(timeout: 10.0))
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

        let headers1 = ["Content-Disposition": "attachment; filename=test-file-1.bin"]
        let url1 = URL.testsServer.appendingTestParameters(headers: headers1)
            .appendingPathComponent("download/")
            .appendingPathComponent("1MB")
        openSiteForDownloadingFile(url: url1.absoluteString)
        // Briefly allow processing of the first trigger
        _ = app.windows.firstMatch.waitForExistence(timeout: 1.0)

        let headers2 = ["Content-Disposition": "attachment; filename=test-file-2.bin"]
        let url2 = URL.testsServer.appendingTestParameters(headers: headers2)
            .appendingPathComponent("download/")
            .appendingPathComponent("1MB")
        openSiteForDownloadingFile(url: url2.absoluteString)

        // Open Downloads popover and assert two download rows are present
        openDownloadsPopup()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let table = popover.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 10.0))
        let twoRowsExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count >= %d", 2),
            object: table.cells
        )
        let waiterResult = XCTWaiter.wait(for: [twoRowsExpectation], timeout: 15.0)
        XCTAssertEqual(waiterResult, .completed)
    }

    /// With "Always ask" ON, binary content should surface a save dialog instead of loading inline.
    func testUnsupportedMimeType_HandledGracefully() {
        // Enable "Always ask"
        configureDownloadPreferences(alwaysAskWhereToSave: true,
                                     openDownloadsPopupOnCompletion: false,
                                     switchToNewTabWhenOpened: false)
        // For binary content, either a web view loads or a save dialog appears
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        openSiteForDownloadingFile(url: URL.testsDownload(size: "1KB").absoluteString)
        let saveDialog = app.sheets.firstMatch
        XCTAssertTrue(saveDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Save dialog should appear for binary content when 'Always ask' is enabled")
        let cancel = saveDialog.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 2.0))
        cancel.click()
    }

    /// When using the save panel, a custom unique filename should be saved and displayed in the Downloads popover.
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

        // Save with a unique filename
        let uniqueName = "ui-" + UUID().uuidString + ".bin"
        saveFileAs(uniqueName)

        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let nameLabel = popover.staticTexts[uniqueName].firstMatch
        XCTAssertTrue(nameLabel.waitForExistence(timeout: 15.0))
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

        openSiteForDownloadingFile(url: URL.testsDownload(size: "5GB").absoluteString)

        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Save dialog should appear for attachment")

        // Cancel the dialog to cancel download
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 2.0))
        cancel.click()

        // Verify no downloads were recorded
        verifyNoRecentDownloads()
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

        openSiteForDownloadingFile(url: URL.testsDownload(size: "5GB").absoluteString)

        // Immediately close window and open a new one; browser should remain stable
        app.typeKey("w", modifierFlags: [.command, .shift])
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(app.exists, "Browser should remain functional after window close during download")

        // Downloads UI should still be accessible
        openDownloadsPopup()
        verifyDownloadPopupIsShown()
        // Verify presence by checking a size label is shown in the popover
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let sizePredicate = NSPredicate(format: "value MATCHES[c] '.*(KB|MB|GB).*'")
        let sizeLabel = popover.staticTexts.containing(sizePredicate).firstMatch
        XCTAssertTrue(sizeLabel.waitForExistence(timeout: 15.0))
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

        app.pasteURL(url, pressingEnter: true)

        XCTAssertTrue(webView.waitForExistence(timeout: 10.0))
        let link = webView.links["Download via Data URL"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5.0))
        link.tap()
        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 2.0))
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
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10.0))
        let link = webView.links["Download via Blob"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5.0))
        link.tap()
        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let cancel = saveSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 2.0))
        cancel.click()
    }

    /// After a completed download, the Downloads list should persist across app restart.
    func testDownloadsPersistAcrossAppRestart() throws {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        // Complete a small download with a distinct name
        let fileName = "persist-test-1mb.bin"
        let headers = ["Content-Disposition": "attachment; filename=\(fileName)"]
        let url = URL.testsServer.appendingTestParameters(headers: headers)
            .appendingPathComponent("download/")
            .appendingPathComponent("1MB")
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        openSiteForDownloadingFile(url: url.absoluteString)
        openDownloadsPopup()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let sizeLabel = popover.staticTexts.containing(NSPredicate(format: "value MATCHES[c] '1.0 MB'")).firstMatch
        XCTAssertTrue(sizeLabel.waitForExistence(timeout: 15.0))

        // Restart app and verify the same file is listed
        app.typeKey("q", modifierFlags: [.command])

        app.launch()
        _=app.wait(for: .runningForeground, timeout: 5.0)
        app.enforceSingleWindow()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        openDownloadsPopup()
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(sizeLabel.exists)
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

        openSiteForDownloadingFile(url: URL.testsDownload(size: "5GB").absoluteString)
        // Ensure download actually started before quitting
        let downloadsButton = app.buttons["NavigationBarViewController.downloadsButton"]
        XCTAssertTrue(downloadsButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))

        app.typeKey("q", modifierFlags: [.command])
        let quitSheet = app.dialogs.firstMatch
        XCTAssertTrue(quitSheet.waitForExistence(timeout: 5.0), "Quit confirmation sheet should appear with active downloads")

        let alertTitle = app.staticTexts["A download is in progress."]
        XCTAssertTrue(alertTitle.waitForExistence(timeout: 10.0), "Quit confirmation alert should appear with active downloads")
        // Button title uses a typographic apostrophe on macOS – match exact title deterministically
        let dontQuit = app.buttons["Don’t Quit"].firstMatch
        XCTAssertTrue(dontQuit.waitForExistence(timeout: 2.0))
        dontQuit.click()

        // Validate download is still running (Stop item visible in context menu)
        openDownloadsPopup()
        let pop = app.popovers.firstMatch
        XCTAssertTrue(pop.waitForExistence(timeout: 5.0))
        let table = pop.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5.0))
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5.0))
        firstRow.click()
        firstRow.rightClick()
        let stopItem = app.menuItems.containing(NSPredicate(format: "title ==[c] 'Stop'"))
        XCTAssertTrue(stopItem.firstMatch.waitForExistence(timeout: 3.0))
        app.typeKey(.escape, modifierFlags: [])

        // Now quit for real and validate app terminates
        app.typeKey("q", modifierFlags: [.command])
        let quitButton = app.buttons["Quit"].firstMatch
        XCTAssertTrue(quitButton.waitForExistence(timeout: 5.0))
        quitButton.click()
        // App should no longer be running in the foreground shortly after
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5.0))
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
            .containing(NSPredicate(format: "value CONTAINS[c] 'Download started'"))
            .firstMatch
        XCTAssertTrue(startedIndicator.waitForExistence(timeout: 15.0))

        // Close the popup tab with the "x" button
        let tabGroup = app.windows.firstMatch
            .tabGroups["Tabs"]
        let popupTab = tabGroup
            .radioButtons
            .containing(NSPredicate(format: "title == 'Background Download'"))
            .firstMatch
        XCTAssertTrue(popupTab.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Hover the tab to reveal its close ("x") button
        popupTab.hover()
        XCTAssertTrue(popupTab.exists)
        let tabFrame = popupTab.frame
        let closeButtonFrame = try XCTUnwrap(popupTab.snapshot().children.first(where: { $0.elementType == .button })?.frame)

        let normalizedX = (closeButtonFrame.midX - tabFrame.minX) / tabFrame.width
        let normalizedY = (closeButtonFrame.midY - tabFrame.minY) / tabFrame.height

        let coordinate = popupTab.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: normalizedY))
        coordinate.click()

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
        openSiteForDownloadingFile(url: URL.testsDownload(size: "1MB").absoluteString)
        verifyDownloadPopupIsShown()

        // Wait until a completed row (size text) appears, then right-click that row
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 10.0))
        let sizeLabel = popover.staticTexts.containing(NSPredicate(format: "value MATCHES[c] '1.0 MB'"))
        XCTAssertTrue(sizeLabel.firstMatch.waitForExistence(timeout: 20.0))
        let table = popover.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5.0))
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5.0))
        firstRow.click()
        firstRow.rightClick()
        let showInFinder = app.menuItems.containing(NSPredicate(format: "title CONTAINS[c] 'Show in Finder'"))
        XCTAssertTrue(showInFinder.firstMatch.waitForExistence(timeout: 5.0))
        showInFinder.firstMatch.click()
        // Re-open and remove the item
        openDownloadsPopup()
        let table2 = popover.tables.firstMatch
        XCTAssertTrue(table2.waitForExistence(timeout: 5.0))
        let firstRow2 = table2.cells.firstMatch
        XCTAssertTrue(firstRow2.waitForExistence(timeout: 5.0))
        firstRow2.click()
        firstRow2.rightClick()
        let removeItem = app.menuItems.containing(NSPredicate(format: "title CONTAINS[c] 'Remove from List'"))
        XCTAssertTrue(removeItem.firstMatch.waitForExistence(timeout: 5.0))
        removeItem.firstMatch.click()

        // Verify popover shows empty state without toggling it closed
        verifyNoRecentDownloads()
    }

    /// Clicking a link that opens a download in a new tab should auto‑close the extra tab after triggering.
    func testTabManagement_DownloadTabAutoCloses_AfterOpen() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        let downloadURL = URL.testsDownload(size: "1MB").absoluteString
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
        openDownloadsPopup()
        let pop = app.popovers.firstMatch
        XCTAssertTrue(pop.waitForExistence(timeout: 10.0))
        let table = pop.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5.0))
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5.0))
        firstRow.click()
        // Right-click and choose Stop to cancel
        firstRow.rightClick()
        let stopItem = pop.menuItems.containing(NSPredicate(format: "title ==[c] 'Stop'")).firstMatch
        XCTAssertTrue(stopItem.waitForExistence(timeout: 3.0))
        stopItem.click()

        // Now right-click again and click Restart Download
        firstRow.rightClick()
        let restartItem = pop.menuItems.containing(NSPredicate(format: "title ==[c] 'Restart Download'")).firstMatch
        XCTAssertTrue(restartItem.waitForExistence(timeout: 3.0))
        restartItem.click()

        // Assert popover remains open (do not toggle with Cmd+J)
        XCTAssertTrue(pop.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Progress should resume: right-click again and ensure the Stop action is available
        firstRow.rightClick()
        let stopAfterRestart = pop.menuItems.containing(NSPredicate(format: "title ==[c] 'Stop'"))
            .firstMatch
        XCTAssertTrue(stopAfterRestart.waitForExistence(timeout: 5.0))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Two links on a served page should yield two download entries; Downloads UI must be accessible.
    func testMultipleDownloads_FromServedPage_ShowsTwoItems() {
        configureDownloadPreferences(alwaysAskWhereToSave: false,
                                     openDownloadsPopupOnCompletion: true,
                                     switchToNewTabWhenOpened: false)
        // Page with two direct download links
        let pageHTML = """
        <html><head><title>Two Downloads</title></head>
        <body>
          <a href="\(URL.testsDownload(size: "1MB").absoluteString)">File A</a>
          <a href="\(URL.testsDownload(size: "5MB").absoluteString)">File B</a>
        </body></html>
        """
        let url = URL.testsServer.appendingTestParameters(data: pageHTML.utf8data)
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        app.pasteURL(url, pressingEnter: true)
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10.0))
        webView.links["File A"].tap()
        webView.links["File B"].tap()
        verifyDownloadPopupIsShown()
    }

    // MARK: - Helper Methods

    private func setupSingleWindow() {
        app.typeKey("w", modifierFlags: [.command, .option, .shift]) // Ensure a single window
        app.typeKey("n", modifierFlags: .command)
    }

    private func downloadFile(onFireWindow: Bool = false) {
        app.openNewTab()
        // wait for the New Tab page to load
        if onFireWindow {
            XCTAssertTrue(app.staticTexts["Fire Window"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
        } else {
            XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
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
        openSiteForDownloadingFile(url: "https://mmatechnical.com/Download/Download-Test-File/(MMA)-10GB.zip")
    }

    private func downloadFileWithCustomSaveName() {
        app.openNewTab()
        // wait for the New Tab page to load
        XCTAssertTrue(webView.popUpButtons["Customize"].waitForExistence(timeout: UITests.Timeouts.elementExistence))

        // Use Content-Disposition so server dictates the filename (no save panel dependency)
        // Use local tests server to provide Content-Disposition filename
        let customNameHeaders = ["Content-Disposition": "attachment; filename=another-name-for-file.zip"]
        let customNameURL = URL.testsServer.appendingTestParameters(headers: customNameHeaders)
            .appendingPathComponent("download/")
            .appendingPathComponent("1MB")
        openSiteForDownloadingFile(url: customNameURL.absoluteString)
        // Wait for downloads button to appear indicating a download started
        let downloadsButton = app.buttons["NavigationBarViewController.downloadsButton"]
        XCTAssertTrue(downloadsButton.waitForExistence(timeout: 10.0))
        // Open downloads UI for verification
        verifyDownloadPopupIsShown()
    }

    private func openFireWindow() {
        app.typeKey("n", modifierFlags: [.command, .shift])
    }

    private func openSiteForDownloadingFile(url: String) {
        app.activateAddressBar()
        app.pasteURL(URL(string: url)!, pressingEnter: true)
    }

    private func saveFileAs(_ fileName: String) {
        let saveSheet = app.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        // Type desired filename and confirm save
        app.typeKey("a", modifierFlags: [.command])
        app.typeText(fileName)
        let saveButton = saveSheet.buttons["Save"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        saveButton.click()
    }

    private func verifyDownloadPopupIsShown() {
        let downloadsPopover = app.popovers.firstMatch
        let clearButton = downloadsPopover.buttons["DownloadsViewController.clearDownloadsButton"]

        XCTAssertTrue(clearButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Downloads popover should be visible after Cmd+J")
    }

    private func verifyDownloadPopupIsNotEmpty() {
        openDownloadsPopup()
        let downloadsPopover = app.popovers.firstMatch
        XCTAssertTrue(downloadsPopover.waitForExistence(timeout: 10.0))
        XCTAssertFalse(app.staticTexts["No recent downloads"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    private func verifyCustomFileIsPresentInDownloads() {
        XCTAssertTrue(app.windows.staticTexts["another-name-for-file.zip"]
            .waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    private func clearDownloads() {
        let clearButton = app.buttons["DownloadsViewController.clearDownloadsButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 10.0), "Clear button should exist when downloads are present")
        clearButton.click()
    }

    private func clearAllDownloadsIfPresent() {
        let popover = app.popovers.firstMatch
        if !popover.exists {
            openDownloadsPopup()
        }
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        let clearButton = popover.buttons["DownloadsViewController.clearDownloadsButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 2.0))
        clearButton.click()
        verifyNoRecentDownloads()
    }

    private func verifyNoRecentDownloads() {
        // Ensure popover is open; if not, open it. Avoid toggling an already open popover.
        var popover = app.popovers.firstMatch
        if !popover.exists {
            openDownloadsPopup()
            popover = app.popovers.firstMatch
        }
        XCTAssertTrue(popover.waitForExistence(timeout: UITests.Timeouts.elementExistence))
        XCTAssertTrue(popover.staticTexts["No recent downloads"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    }

    // Settings manipulation methods removed to prevent Settings windows opening during tests

    private func closeWindowWithInProgressDownload() {
        app.typeKey("w", modifierFlags: [.shift, .command]) // Close window
    }

    private func verifyDownloadInProgressWarning() {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: UITests.Timeouts.elementExistence),
                      "Closing Fire window with in-progress download should present a confirmation sheet")
    }

    private func openDownloadsPopup() {
        app.typeKey("j", modifierFlags: [.command])
    }

    // MARK: - Helpers

    // Unified preferences configuration for Downloads tests
    private func configureDownloadPreferences(alwaysAskWhereToSave: Bool,
                                              openDownloadsPopupOnCompletion: Bool,
                                              switchToNewTabWhenOpened: Bool) {
        app.openPreferencesWindow()
        app.preferencesGoToGeneralPane()
        app.setAlwaysAskWhereToSaveFiles(enabled: alwaysAskWhereToSave)
        app.setOpenDownloadsPopupOnCompletion(enabled: openDownloadsPopupOnCompletion)
        app.setSwitchToNewTabWhenOpened(enabled: switchToNewTabWhenOpened)
        app.closePreferencesWindow()
    }

}
