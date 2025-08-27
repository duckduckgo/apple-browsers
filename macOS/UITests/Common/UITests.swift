//
//  UITests.swift
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

import Foundation
import XCTest

/// Helper values for the UI tests
enum UITests {
    /// Timeout constants for different test requirements
    enum Timeouts {
        /// Mostly, we use timeouts to wait for element existence. This is about 3x longer than needed, for CI resilience
        static let elementExistence: Double = 5.0
        /// The fire animation time has environmental dependencies, so we want to wait for completion so we don't try to type into it
        static let fireAnimation: Double = 30.0
        /// Navigation timeout for page loads and network requests
        static let navigation: Double = 30.0
        /// Local test server timeout for localhost connections
        static let localTestServer: Double = 15.0
    }

    /// A page simple enough to test favorite, bookmark, and history storage
    /// - Parameter title: The title of the page to match
    /// - Returns: A URL that can be served by `tests-server`
    static func simpleServedPage(titled title: String) -> URL {
        return URL.testsServer
            .appendingTestParameters(data: """
            <html>
            <head>
            <title>\(title)</title>
            </head>
            <body>
            <p>Sample text for \(title)</p>
            </body>
            </html>
            """.utf8data)
    }

    static func randomPageTitle(length: Int) -> String {
        return String(UUID().uuidString.prefix(length))
    }

    /// This is intended for setting an autocomplete checkbox state that extends across all test cases and is only run once in the class override
    /// setup() of the case. Setting the autocomplete checkbox state for an individual test shouldn't start and terminate the app, as this function
    /// does.
    /// - Parameter requestedToggleState: How the autocomplete checkbox state should be set
    static func setAutocompleteToggleBeforeTestcaseRuns(_ requestedToggleState: Bool) {
        let app = XCUIApplication.setUp()

        let settings = app.menuItems["MainMenu.preferencesMenuItem"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "Reset bookmarks menu item didn't become available in a reasonable timeframe."
        )

        settings.click()
        let generalPreferencesButton = app.buttons["PreferencesSidebar.generalButton"]
        let autocompleteToggle = app.checkBoxes["PreferencesGeneralView.showAutocompleteSuggestions"]
        XCTAssertTrue(
            generalPreferencesButton.waitForExistence(timeout: UITests.Timeouts.elementExistence),
            "The user settings appearance section button didn't become available in a reasonable timeframe."
        )
        generalPreferencesButton.click(forDuration: 0.5, thenDragTo: generalPreferencesButton)

        let currentToggleState = try? XCTUnwrap(
            autocompleteToggle.value as? Bool,
            "It wasn't possible to get the \"Autocomplete\" value as a Bool"
        )

        switch (requestedToggleState, currentToggleState) { // Click autocomplete toggle if it is different than our request
        case (false, true), (true, false):
            autocompleteToggle.click()
        default:
            break
        }
        app.terminate()
    }

    /// A debug function that is going to need some other functionality in order to be useful for debugging address bar focus issues
    static func openVanillaBrowser() {
        let app = XCUIApplication.setUp()
        let openVanillaBrowser = app.menuItems["MainMenu.openVanillaBrowser"]
        openVanillaBrowser.clickAfterExistenceTestSucceeds()
        app.typeKey("w", modifierFlags: [.command, .option])
    }

    /// Avoid some first-run states that we aren't testing.
    static func firstRun() {
        let notificationCenter = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        if notificationCenter.exists { // If tests-server is asking for network permissions, deny them.
            notificationCenter.typeKey(.escape, modifierFlags: [])
        }
        let app = XCUIApplication.setUp()
        app.typeKey("n", modifierFlags: .command)
        app.typeKey("w", modifierFlags: [.command, .option])
        app.terminate()
    }
}

class TestFailureObserver: NSObject, XCTestObservation {
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        print("Failed test with name: \(testCase.name)")
        let screenshotName = "\(testCase.name)-failure"
        testCase.takeScreenshot(screenshotName)
    }
}

class UITestCase: XCTestCase {
    private static let failureObserver = TestFailureObserver()
    private var cleanupPaths: Set<String> = []

    override class func setUp() {
        super.setUp()
        XCTestObservationCenter.shared.addTestObserver(failureObserver)

        Logger.log("Resetting environment for the first run")
        UITests.firstRun()
    }

    override class func tearDown() {
        XCTestObservationCenter.shared.removeTestObserver(failureObserver)
        super.tearDown()
    }

    override func tearDown() {
        cleanupTrackedFiles()
        cleanupPaths.removeAll()
        super.tearDown()
    }

    static func log(_ message: String) {
        Logger.log(message)
    }

    // MARK: - File Management Methods

    /// Track a file path for cleanup after the test completes
    /// - Parameter path: The absolute file path to track for cleanup
    func trackForCleanup(_ path: String) {
        cleanupPaths.insert(path)
    }

    /// Read a file via the local test server to bypass permission issues
    /// - Parameter filePath: The absolute file path to read
    /// - Returns: The file data
    /// - Throws: Error if the file cannot be read or server request fails
    func readFileViaLocalServer(filePath: String) throws -> Data {
        let readURL = URL.testsServer.appendingParameter(name: "readFile", value: filePath)

        let session = URLSession(configuration: .ephemeral)
        let request = URLRequest(url: readURL, cachePolicy: .reloadIgnoringLocalCacheData)

        var outResponse: URLResponse?
        var resultData: Data?
        var resultError: Error?
        var retry = 0
        repeat {
            if retry > 0 {
                Thread.sleep(forTimeInterval: 0.5)
            }
            let expectation = expectation(description: "File read request completed")

            let task = session.dataTask(with: request) { data, response, error in
                outResponse = response
                resultError = error
                resultData = data
                if error == nil,
                   let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    resultError = NSError(domain: "FileReadError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }
                expectation.fulfill()
            }
            task.resume()

            let result = XCTWaiter.wait(for: [expectation], timeout: UITests.Timeouts.elementExistence)
            XCTAssertEqual(result, .completed, "File read request should complete")

            Logger.log("Response #\(retry): \(outResponse ??? "<nil>"), error: \(resultError ??? "<nil>"), data: \(resultData ??? "<nil>")")
            retry += 1
        } while resultData?.count == 0 && retry < 5

        if let error = resultError {
            throw error
        }

        guard let data = resultData else {
            throw NSError(domain: "FileReadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received from server"])
        }

        return data
    }

    /// Clean up all tracked files using the local test server
    private func cleanupTrackedFiles() {
        guard !cleanupPaths.isEmpty else { return }

        let paths = Array(cleanupPaths)
        let pathsQuery = paths.joined(separator: ",")
        let cleanupURL = URL.testsServer.appendingParameter(name: "deleteFiles", value: pathsQuery)

        let session = URLSession(configuration: .ephemeral)
        let request = URLRequest(url: cleanupURL, cachePolicy: .reloadIgnoringLocalCacheData)

        let expectation = expectation(description: "Cleanup request completed")
        let task = session.dataTask(with: request) { _, _, _ in
            expectation.fulfill()
        }
        task.resume()

        // Wait but don't fail the test if cleanup is slow
        _ = XCTWaiter.wait(for: [expectation], timeout: UITests.Timeouts.elementExistence)
    }
}

struct Logger {
    static var debug: Logger = Logger()

    func log(_ message: String) {
        Logger.log(message)
    }

    /// Log a debug message using XCTest's private debug log handler
    /// - Parameter message: The message to log
    static func log(_ message: String) {
        let currentContextSelector = NSSelectorFromString("currentContext")
        let logFormatSelector = NSSelectorFromString("_recordActivityMessageWithFormat:")

        guard let context = XCTContext.perform(currentContextSelector)?.takeUnretainedValue() else {
            fatalError("Could not retrieve current XCTContext")
        }
        // Escape any %-escaped values in the message before passing it as the format string
        let escapedMessage = message.replacingOccurrences(of: "%", with: "%%")
        _ = context.perform(logFormatSelector, with: escapedMessage)
    }
}

extension XCTestCase {
    func takeScreenshot(_ name: String) {
        let fullScreenshot = XCUIScreen.main.screenshot()
        let screenshot = XCTAttachment(screenshot: fullScreenshot)
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

infix operator ???: NilCoalescingPrecedence
/// Provide value debug description or ??? "defaultValue" - to be used for logging like:
/// ```
/// Logger.general.debug("event received: \(event ??? "<nil>")")
/// ```
public func ??? <T>(optionalValue: T?, defaultValue: @autoclosure () -> String) -> String {
    optionalValue.map { String(describing: $0) } ?? defaultValue()
}
