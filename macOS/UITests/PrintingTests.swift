//
//  PrintingTests.swift
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

import Foundation
import XCTest

class PrintingTests: UITestCase {
    private var app: XCUIApplication!
    private var pdfURL: URL!
    private var addressBarTextField: XCUIElement!
    private var printMenuItem: XCUIElement!
    private var saveAsMenuItem: XCUIElement!
    private var printDialog: XCUIElement!
    private var saveDialog: XCUIElement!

    override class func setUp() {
        super.setUp()
        UITests.firstRun()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"

        // Create PDF URL using the test server pattern
        let testPDFBundle = Bundle(for: type(of: self))
        let testPDFPath = try XCTUnwrap(testPDFBundle.path(forResource: "test", ofType: "pdf"), "Could not find test.pdf in test bundle")
        pdfURL = URL(fileURLWithPath: testPDFPath)

        // Initialize UI elements
        addressBarTextField = app.windows.textFields["AddressBarViewController.addressBarTextField"]
        printMenuItem = app.menuItems.element(matching: NSPredicate(format: "identifier == 'PDFContextMenu.print'"))
        saveAsMenuItem = app.menuItems.element(matching: NSPredicate(format: "identifier == 'PDFContextMenu.saveAs'"))
        printDialog = app.sheets.containing(.button, identifier: "Print").firstMatch
        saveDialog = app.sheets.containing(.button, identifier: "Save").firstMatch

        app.launch()
        app.typeKey("w", modifierFlags: [.command, .option, .shift]) // Close all windows
        app.typeKey("n", modifierFlags: .command) // New window
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Test Cases

    func test_pdf_contextMenuPrint_opensPrintDialog() throws {
        // Open PDF
        let pdfWebView = openPDFInBrowser()

        XCTAssertTrue(
            pdfWebView.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "PDF WebView did not appear in a reasonable timeframe."
        )

        pdfWebView.rightClick()

        try app.clickContextMenuItem(matching: { $0.identifier == "PDFContextMenu.print" })

        // Wait for print dialog to appear
        XCTAssertTrue(
            printDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Print dialog did not appear in a reasonable timeframe."
        )

        // Cancel the print dialog
        let cancelButton = printDialog.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    func test_pdf_keyboardShortcutPrint_opensPrintDialog() throws {
        // Open PDF
        _=openPDFInBrowser()

        // Use Cmd+P to print
        app.typeKey("p", modifierFlags: [.command])

        // Wait for print dialog to appear
        XCTAssertTrue(
            printDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Print dialog did not appear in a reasonable timeframe."
        )
        // Cancel the print dialog
        let cancelButton = printDialog.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
    }

    func test_pdf_contextMenuSaveAs_opensDialogAndSavesPDF() throws {
        // Open PDF
        let pdfWebView = openPDFInBrowser()

        // Right click PDF
        pdfWebView.rightClick()

        try app.clickContextMenuItem(matching: { $0.identifier == "PDFContextMenu.saveAs" })

        // Wait for save dialog to appear
        XCTAssertTrue(
            saveDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save dialog did not appear in a reasonable timeframe."
        )

        // Get default save location and create a unique filename
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let uniqueFilename = "test-\(UUID().uuidString.prefix(8)).pdf"
        let expectedSaveURL = downloadsURL.appendingPathComponent(uniqueFilename)
        defer {
            try? FileManager.default.removeItem(at: expectedSaveURL)
        }

        // Select Downloads folder destination
        if !app.popUpButtons["Where:"].menuItems["Downloads"].firstMatch.exists {
            app.popUpButtons["Where:"].firstMatch.click()
            app.menuItems["Downloads"].firstMatch.click()
        }

        // Modify the filename in the save dialog
        let filenameField = saveDialog.textFields.firstMatch
        if filenameField.exists {
            filenameField.click()
            app.typeKey("a", modifierFlags: [.command]) // select all
            filenameField.typeText(uniqueFilename)
        }

        // Click Save button
        let saveButton = saveDialog.buttons["Save"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save button did not appear in save dialog in a reasonable timeframe."
        )

        saveButton.click()

        // Wait for file to be saved
        let fileSavedExpectation = expectation(description: "PDF file should be saved")
        let checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: expectedSaveURL.path) {
                fileSavedExpectation.fulfill()
                timer.invalidate()
            }
        }

        wait(for: [fileSavedExpectation], timeout: 10.0)
        checkTimer.invalidate()

        // Verify file was saved and has correct content
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedSaveURL.path),
            "PDF file was not saved to expected location."
        )

        // Verify file size is reasonable (should be > 0 bytes)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: expectedSaveURL.path)
        let fileSize = fileAttributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize, "Could not get file size of saved PDF.")
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 0, "Saved PDF file is empty.")

        // Clean up
        try? FileManager.default.removeItem(at: expectedSaveURL)
    }

    func test_pdf_keyboardShortcutSaveAs_opensDialogAndSavesPDF() throws {
        // Open PDF
        _=openPDFInBrowser()

        // Use Cmd+S to save
        app.typeKey("s", modifierFlags: [.command])

        // Wait for save dialog to appear
        XCTAssertTrue(
            saveDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save dialog did not appear in a reasonable timeframe."
        )

        // Get default save location and create a unique filename
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let uniqueFilename = "test-keyboard-\(UUID().uuidString.prefix(8)).pdf"
        let expectedSaveURL = downloadsURL.appendingPathComponent(uniqueFilename)

        // Select Downloads folder destination
        if !app.popUpButtons["Where:"].menuItems["Downloads"].firstMatch.exists {
            app.popUpButtons["Where:"].firstMatch.click()
            app.menuItems["Downloads"].firstMatch.click()
        }

        // Modify the filename in the save dialog
        let filenameField = saveDialog.textFields.firstMatch
        if filenameField.exists {
            filenameField.click()
            app.typeKey("a", modifierFlags: [.command]) // select all
            filenameField.typeText(uniqueFilename)
        }

        // Click Save button
        let saveButton = saveDialog.buttons["Save"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save button did not appear in save dialog in a reasonable timeframe."
        )

        saveButton.click()

        // Wait for file to be saved
        let fileSavedExpectation = expectation(description: "PDF file should be saved")
        let checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: expectedSaveURL.path) {
                fileSavedExpectation.fulfill()
                timer.invalidate()
            }
        }

        wait(for: [fileSavedExpectation], timeout: 10.0)
        checkTimer.invalidate()

        // Verify file was saved
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedSaveURL.path),
            "PDF file was not saved to expected location."
        )

        // Verify file size is reasonable
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: expectedSaveURL.path)
        let fileSize = fileAttributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize, "Could not get file size of saved PDF.")
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 0, "Saved PDF file is empty.")

        // Clean up
        try? FileManager.default.removeItem(at: expectedSaveURL)
    }

    func test_pdf_saveToPDF_createsValidPDFFile() throws {
        // Open PDF
        _ = openPDFInBrowser()

        // Use Cmd+P to open print dialog
        app.typeKey("p", modifierFlags: [.command])

        // Wait for print dialog to appear
        XCTAssertTrue(
            printDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Print dialog did not appear in a reasonable timeframe."
        )

        // Click PDF menu button in print dialog
        let pdfMenuButton = printDialog.menuButtons["PDF"]
        XCTAssertTrue(
            pdfMenuButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "PDF menu button did not appear in print dialog in a reasonable timeframe."
        )

        pdfMenuButton.click()

        // Select "Save as PDF…" from the menu
        let saveAsPDFMenuItem = app.menuItems["Save as PDF…"]
        XCTAssertTrue(
            saveAsPDFMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save as PDF menu item did not appear in a reasonable timeframe."
        )

        saveAsPDFMenuItem.click()

        // Wait for save dialog to appear
        XCTAssertTrue(
            saveDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save dialog did not appear in a reasonable timeframe."
        )

        // Create unique filename for validation test
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let validationFilename = "validation-test-\(UUID().uuidString.prefix(8)).pdf"
        let validationSaveURL = downloadsURL.appendingPathComponent(validationFilename)
        defer {
            try? FileManager.default.removeItem(at: validationSaveURL)
        }

        // Select Downloads folder destination
        if !app.popUpButtons["Where:"].menuItems["Downloads"].firstMatch.exists {
            app.popUpButtons["Where:"].firstMatch.click()
            app.menuItems["Downloads"].firstMatch.click()
        }

        // Set filename in the save dialog
        let filenameField = saveDialog.textFields.firstMatch
        if filenameField.exists {
            filenameField.click()
            app.typeKey("a", modifierFlags: [.command]) // select all
            filenameField.typeText(validationFilename)
        }

        // Click Save button
        let saveButton = saveDialog.buttons["Save"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save button did not appear in save dialog in a reasonable timeframe."
        )

        saveButton.click()

        // Wait for file to be saved
        let fileSavedExpectation = expectation(description: "PDF file should be saved for validation")
        let checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: validationSaveURL.path) {
                fileSavedExpectation.fulfill()
                timer.invalidate()
            }
        }

        wait(for: [fileSavedExpectation], timeout: 10.0)
        checkTimer.invalidate()

        // Validate PDF file exists
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: validationSaveURL.path),
            "PDF file was not saved for validation."
        )

        // Open the saved PDF in a new tab to validate content
        app.typeKey("t", modifierFlags: [.command]) // New tab

        // Wait for new tab and address bar
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Address bar text field did not appear in new tab in a reasonable timeframe."
        )

        // Load the saved PDF
        addressBarTextField.pasteURL(validationSaveURL, pressingEnter: true)

        getPdfViewElement()
    }

    func test_pdf_contextMenuOpenWithPreview_opensPreviewAndValidatesContent() throws {
        // Open PDF in browser
        let pdfWebView = openPDFInBrowser()

        // Right-click on PDF to open context menu
        pdfWebView.rightClick()

        // Click "Open with Preview" menu item
        try app.clickContextMenuItem(matching: { $0.title == "Open with Preview" })

        // Get Preview app
        let previewApp = XCUIApplication(bundleIdentifier: "com.apple.Preview")

        // Wait for Preview app to become active
        let previewActivatedExpectation = expectation(description: "Preview app should become active")
        let activationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if previewApp.state == .runningForeground {
                previewActivatedExpectation.fulfill()
                timer.invalidate()
            }
        }

        wait(for: [previewActivatedExpectation], timeout: 10.0)
        activationTimer.invalidate()

        XCTAssertEqual(previewApp.state, .runningForeground, "Preview app should be running in foreground")

        // Get the specific PDF window (to avoid interference from other windows)
        let previewWindow = previewApp.windows.matching(NSPredicate(format: "title CONTAINS[c] 'test.pdf'")).firstMatch
        XCTAssertTrue(
            previewWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "PDF window should exist in Preview."
        )

        // Validate that "TestPDF" text is present in the PDF window
        let testText = previewWindow.staticTexts.element(matching: NSPredicate(format: "value LIKE '*TestPDF*'")).firstMatch

        XCTAssertTrue(
            testText.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Preview window should display 'TestPDF' text from PDF."
        )

        // Close the window using the close button
        let closeButton = previewWindow.buttons["_XCUI:CloseWindow"]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Close button should exist in Preview window."
        )

        closeButton.click()

        // Verify window is closed by checking it no longer exists
        XCTAssertTrue(
            previewWindow.waitForNonExistence(timeout: 2.0),
            "PDF window should be closed after clicking close button."
        )

        // Return focus to our main app
        app.activate()
    }

    func test_pinnedTab_printingBehaviorAcrossWindows() throws {
        var firstWindow = app.windows.firstMatch

        // Step 1: Open Settings to ensure pinned tabs are shared across all windows
        app.typeKey(",", modifierFlags: [.command])

        // Click General button in sidebar
        let generalButton = firstWindow.buttons["PreferencesSidebar.generalButton"]
        XCTAssertTrue(
            generalButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "General button should exist in settings sidebar."
        )
        generalButton.click()

        // Ensure pinned tabs setting is "Shared across all windows"
        let pinnedTabsPopUp = firstWindow.popUpButtons["PreferencesGeneralView.pinnedTabsModePicker"]
        XCTAssertTrue(
            pinnedTabsPopUp.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Pinned tabs settings popup does not exist or is not visible."
        )
        if pinnedTabsPopUp.value as? String != "Shared across all windows" {
            pinnedTabsPopUp.click()
            app.menuItems["Shared across all windows"].click()
        }
        XCTAssertEqual(pinnedTabsPopUp.value as? String, "Shared across all windows")

        // Step 2: Open PDF in current window
        app.typeKey("t", modifierFlags: [.command])
        _ = openPDFInBrowser()

        // Step 3: Pin the tab using Window -> Pin Tab menu
        // Use Window menu to pin the current tab
        let windowMenu = app.menuBars.menuBarItems["Window"]
        XCTAssertTrue(
            windowMenu.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Window menu should be available."
        )
        windowMenu.click()

        let pinTabMenuItem = app.menuItems["Pin Tab"]
        XCTAssertTrue(
            pinTabMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Pin Tab menu item should be available in Window menu."
        )
        pinTabMenuItem.click()

        // Step 4: Switch to pinned tab (cmd+1)
        app.typeKey("1", modifierFlags: [.command])

        getPdfViewElement(in: firstWindow)

        // Step 5: Open print dialog in first window
        app.typeKey("p", modifierFlags: [.command])

        let printDialogWindow1 = { firstWindow.sheets.containing(.button, identifier: "Print").firstMatch }
        XCTAssertTrue(
            printDialogWindow1().waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Print dialog should appear in first window."
        )

        // Step 6: Open new window (cmd+n)
        app.typeKey("n", modifierFlags: [.command])

        firstWindow = app.windows.element(boundBy: 1) // First window: Background window
        var secondWindow = app.windows.firstMatch // Second window: Active window
        XCTAssertTrue(
            secondWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Second window should open."
        )

        XCTAssertEqual(firstWindow.title, "test.pdf")
        XCTAssertEqual(secondWindow.title, "New Tab")

        // Step 7: Switch to pinned tab in second window (cmd+1)
        app.typeKey("1", modifierFlags: [.command])

        // Step 8: Validate no print dialog is shown in the new window
        let printDialogWindow2 = { secondWindow.sheets.containing(.button, identifier: "Print").firstMatch }
        XCTAssertTrue(
            printDialogWindow2().waitForNonExistence(timeout: 2.0),
            "Print dialog should NOT appear in second window automatically."
        )

        // Step 9: Validate print dialog is closed in first window
        XCTAssertTrue(
            printDialogWindow1().waitForNonExistence(timeout: 2.0),
            "Print dialog should be closed in first window after switching tabs."
        )

        // Validate content in second window
        getPdfViewElement(in: secondWindow)

        // Step 10: Hit cmd+p in the 2nd window
        app.typeKey("p", modifierFlags: [.command])

        XCTAssertTrue(
            printDialogWindow2().waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Print dialog should appear in second window after cmd+p."
        )

        // Step 11: Save as PDF and validate
        let pdfMenuButton = printDialogWindow2().menuButtons["PDF"]
        XCTAssertTrue(
            pdfMenuButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "PDF menu button should exist in print dialog."
        )
        pdfMenuButton.click()

        let saveAsPDFMenuItem = app.menuItems["Save as PDF…"]
        XCTAssertTrue(
            saveAsPDFMenuItem.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save as PDF menu item should appear."
        )
        saveAsPDFMenuItem.click()

        // Handle save dialog
        let saveDialog = secondWindow.sheets.containing(.button, identifier: "Save").firstMatch
        XCTAssertTrue(
            saveDialog.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Save dialog should appear."
        )

        // Create unique filename
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let pinnedTabFilename = "pinned-tab-test-\(UUID().uuidString.prefix(8)).pdf"
        let pinnedTabSaveURL = downloadsURL.appendingPathComponent(pinnedTabFilename)
        defer {
            try? FileManager.default.removeItem(at: pinnedTabSaveURL)
        }

        // Select Downloads folder destination
        if !saveDialog.popUpButtons["Where:"].menuItems["Downloads"].firstMatch.exists {
            saveDialog.popUpButtons["Where:"].firstMatch.click()
            app.menuItems["Downloads"].firstMatch.click()
        }

        // Set filename
        let filenameField = saveDialog.textFields.firstMatch
        if filenameField.exists {
            filenameField.click()
            app.typeKey("a", modifierFlags: [.command]) // select all
            filenameField.typeText(pinnedTabFilename)
        }

        saveDialog.buttons["Save"].click()

        // Wait for file to be saved
        let fileSavedExpectation = expectation(description: "PDF file should be saved from pinned tab")
        let checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: pinnedTabSaveURL.path) {
                fileSavedExpectation.fulfill()
                timer.invalidate()
            }
        }

        wait(for: [fileSavedExpectation], timeout: 10.0)
        checkTimer.invalidate()

        // Step 12: Validate saved file by opening it in second window
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: pinnedTabSaveURL.path),
            "PDF file should be saved from pinned tab."
        )

        // Open new tab in second window and load the saved PDF
        app.typeKey("t", modifierFlags: [.command])

        let addressBarWindow2 = secondWindow.textFields["AddressBarViewController.addressBarTextField"]
        XCTAssertTrue(
            addressBarWindow2.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Address bar should exist in second window."
        )

        addressBarWindow2.pasteURL(pinnedTabSaveURL, pressingEnter: true)

        // Validate content in second window
        getPdfViewElement(in: secondWindow)

        // Step 13: Additional window switching validation
        // switch to the pinned tab
        app.typeKey("1", modifierFlags: [.command])
        // Hit cmd+p in the 2nd window again
        app.typeKey("p", modifierFlags: [.command])

        XCTAssertTrue(
            printDialogWindow2().waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Print dialog should appear in second window after second cmd+p."
        )

        // Activate the first window
        app.typeKey("`", modifierFlags: [.command])
        firstWindow = app.windows.firstMatch // First window: Active window
        secondWindow = app.windows.element(boundBy: 1) // Second window: Background window

        // Make sure the print dialog in the 2nd window disappears
        XCTAssertTrue(
            printDialogWindow2().waitForNonExistence(timeout: 2),
            "Print dialog should disappear from second window after activating first window."
        )

        // Make sure there's no print dialog in 1st window
        XCTAssertTrue(
            printDialogWindow1().waitForNonExistence(timeout: 2),
            "Print dialog should not exist in first window after activating it."
        )

        // Hit cmd+p in 1st window
        app.typeKey("p", modifierFlags: [.command])

        // Make sure dialog appears in first window
        XCTAssertTrue(
            printDialogWindow1().waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Print dialog should appear in first window after cmd+p."
        )

        // Make sure the print dialog in the 2nd window doesn't exist
        XCTAssertTrue(
            printDialogWindow2().waitForNonExistence(timeout: 2),
            "Print dialog should not appear in the second window after starting print in 1st window."
        )

        // Cancel the print dialog in first window
        let cancelButton = printDialogWindow1().buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
    }

}

// MARK: - Helper Methods

private extension PrintingTests {

    /// Opens the test PDF in the browser
    func openPDFInBrowser() -> XCUIElement {
        XCTAssertTrue(
            addressBarTextField.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Address bar text field did not appear in a reasonable timeframe."
        )

        addressBarTextField.pasteURL(pdfURL, pressingEnter: true)

        return getPdfViewElement()
    }

    @discardableResult
    func getPdfViewElement(in root: XCUIElement? = nil) -> XCUIElement {
        let element = (root ?? app).groups.containing(NSPredicate(format: "elementType == %lu AND value LIKE 'TestPDF*'", XCUIElement.ElementType.staticText.rawValue)).firstMatch

        XCTAssertTrue(
            element.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "PDF View did not appear in a reasonable timeframe."
        )

        return element
    }

}
