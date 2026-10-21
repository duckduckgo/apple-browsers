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

import Carbon
import Foundation
import ObjectiveC
import os.log
import SharedTestUtilities
@_exported import UITestingSupport
import XCTest

/// Helper values for the UI tests
enum UITests {
    /// Timeout constants for different test requirements
    enum Timeouts {
        static let elementExistence = UITestTimeouts.elementExistence
        static let fireAnimation = UITestTimeouts.fireAnimation
        static let navigation = UITestTimeouts.navigation
        static let localTestServer = UITestTimeouts.localTestServer
    }

    /// A page simple enough to test favorite, bookmark, and history storage
    /// - Parameter title: The title of the page to match
    /// - Parameter body: The body of the page to match
    /// - Returns: A URL that can be served by `tests-server`
    static func simpleServedPage(titled title: String) -> URL {
        simpleServedPage(titled: title, body: "<p>Sample text for \(title)</p>")
    }

    static func simpleServedPage(titled title: String, body: String) -> URL {
        return URL.testsServer
            .appendingTestParameters(data: """
            <html>
            <head>
            <title>\(title)</title>
            </head>
            <body>
            \(body)
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
        guard #available(macOS 13, *) else {
            // Xcode 13's accessibility query for this Settings checkbox hangs on Monterey.
            // Prepare the class fixture before launch, using the app's persisted preference.
            let app = XCUIApplication()
            if app.state != .notRunning {
                app.terminate()
            }
            do {
                let bundleID = try XCTUnwrap(app.bundleID)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
                process.arguments = ["write", bundleID, "preferences.appearance.show-autocomplete-suggestions",
                                     "-bool", requestedToggleState ? "true" : "false"]
                try process.run()
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0, "Could not configure the autocomplete fixture")
            } catch {
                XCTFail("Could not configure the autocomplete fixture: \(error)")
            }
            return
        }
        let app = XCUIApplication.setUp()
        // Settings opens as a tab, so it needs a browser window to host it
        app.enforceSingleWindow()
        app.openGeneralPreferences()
        let autocompleteToggle = app.preferencesWindow.checkBoxes["PreferencesGeneralView.showAutocompleteSuggestions"]
        autocompleteToggle.toggleCheckboxIfNeeded(to: requestedToggleState, validate: true, ensureHittable: app.ensureHittable)
        app.terminate()
    }

    /// Reset once before a test class configures its fixture.
    /// Legacy runners use separate processes for methods and reset only the first method of each class.
    static func resetAppState() throws {
        guard ProcessInfo.processInfo.environment["UITEST_RESET_CLASS_STATE"] != "0" else { return }
        let application = XCUIApplication()
        if application.state != .notRunning {
            application.terminate()
        }
        let bundleID = try XCTUnwrap(application.bundleID, "The test configuration must identify the target app")
        let script = try XCTUnwrap(Bundle(for: UITestCase.self).url(forResource: "pre-run", withExtension: "sh", subdirectory: "ui-tests"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--reset-only", "--bundle-id", bundleID]
        process.environment = ProcessInfo.processInfo.environment
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "UITestStateReset", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Could not reset the test app state"])
        }
    }

    /// A debug function that is going to need some other functionality in order to be useful for debugging address bar focus issues
    static func openVanillaBrowser() {
        let app = XCUIApplication.setUp()
        let openVanillaBrowser = app.menuItems["MainMenu.openVanillaBrowser"]
        openVanillaBrowser.clickAfterExistenceTestSucceeds()
        app.typeKey("w", modifierFlags: [.command, .option])
    }

    /// Avoid some first-run states that we aren't testing.
    static func firstRun(_ callback: (XCUIApplication) -> Void = { _ in }) {
        let app = XCUIApplication.setUp()
        app.typeKey("n", modifierFlags: .command)
        callback(app)
        app.typeKey("w", modifierFlags: [.command, .option])
        app.terminate()
    }
}

class TestFailureObserver: NSObject, XCTestObservation {

    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard !issue.description.hasPrefix("Runtime Issue:") else {
            Logger.log("🟣 \(issue)")
            return
        }
        Logger.log("🔴 Issue recorded: \(issue)")
        if XCUIApplication.notificationCenter.buttons.firstMatch.exists {
            let descr = (try? XCUIApplication.notificationCenter.snapshot().toDictionary(ignoringElementsOfType: [.menu, .menuItem, .menuBar])) ??? "<nil>"
            Logger.log("⚠️ TCC prompt shown: \(descr)")
        }
        Logger.log("🌐 tests-server \(Self.probeTestsServer())")
        let screenshotName = "\(testCase.name)-failure"
        testCase.takeScreenshot(screenshotName)
    }

    private static func probeTestsServer() -> String {
        let url = URL.testsServer.appendingTestParameters(data: Data("ok".utf8))
        var result: String?
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ??? "nil"
            result = "status=\(status) error=\(error ??? "nil") body=\(data.flatMap { String(data: $0, encoding: .utf8) } ??? "nil")"
        }.resume()
        let deadline = Date().addingTimeInterval(UITests.Timeouts.elementExistence)
        while result == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return result ?? "timeout"
    }
}

@objc(UITestCase)
class UITestCase: XCTestCase {
    var app: XCUIApplication!

    private static let failureObserver = TestFailureObserver()
    private var cleanupPaths: Set<String> = []

    private static var systemPermissionPromptPollingTimer: Timer?
    var isSystemPermissionPromptPollingTimerEnabled: Bool { true }

    override class func setUp() {
        Logger.log("🟠 class \(self.self).setUp()")
        // Set up method swizzling to enable precise keyboard/mouse event simulation.
        // This allows tests to simulate "hold key" scenarios (keyDown/keyUp with proper timing)
        // and middle-click events that aren't directly supported by XCTest's standard APIs.
        setupXCPointerEventPathSwizzling()
        _ = XCUIDevice.swizzlePerformWithKeyModifiersOnce
        super.setUp()
        XCTestObservationCenter.shared.addTestObserver(failureObserver)
        do {
            try UITests.resetAppState()
            if ProcessInfo.processInfo.environment["UITEST_RESET_CLASS_STATE"] != "0" {
                UITests.firstRun()
            }
        } catch {
            XCTFail("Could not prepare test class: \(error)")
        }
    }

    /// System TCC alerts can appear asynchronously mid-test and steal key focus. A repeating timer
    /// on the main run loop fires during XCTest waits and dismisses them before the next click.
    private func startSystemPermissionPromptDismissTimerIfNeeded() {
        // Xcode 13 cannot synthesize another UI event from the run loop while an
        // event is pending. Its normal interruption monitor still handles prompts.
        guard #available(macOS 13, *) else { return }
        guard Self.systemPermissionPromptPollingTimer == nil else { return }

        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            Logger.log("⏰ Checking for TCC prompts")
            _ = XCUIApplication.notificationCenter.dismissSystemPermissionPromptIfPresent(logIfNotFound: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        Self.systemPermissionPromptPollingTimer = timer
    }

    override class func tearDown() {
        systemPermissionPromptPollingTimer?.invalidate()
        systemPermissionPromptPollingTimer = nil
        XCTestObservationCenter.shared.removeTestObserver(failureObserver)
        super.tearDown()
    }

    // Handles both super.setUp() and super.setUpWithError() calls.
    override func setUpWithError() throws {
        Logger.log("🟠 \(self.className).setUpWithError()")
        try super.setUpWithError()

        continueAfterFailure = false

        addUIInterruptionMonitor(withDescription: "Interruption Monitor") { element in
            Logger.log("🟠 Received interruption event: \((try? element.snapshot().toDictionary()) ??? "<nil>")")
            return XCUIApplication.notificationCenter.dismissSystemPermissionPromptIfPresent(logIfNotFound: false)
        }

        if isSystemPermissionPromptPollingTimerEnabled {
            startSystemPermissionPromptDismissTimerIfNeeded()
        }
    }

    override func tearDown() {
        cleanupTrackedFiles()
        cleanupPaths.removeAll()
        super.tearDown()
    }

    /// Swizzles XCPointerEventPath private methods to call original implementation
    /// Uses once token pattern to ensure swizzling happens only once
    private static func setupXCPointerEventPathSwizzling() {
        // Using static variable for once semantics (equivalent to dispatch_once)
        struct OnceToken {
            static let token: Void = {
                guard let pointerEventPathClass = NSClassFromString("XCPointerEventPath") else {
                    print("Warning: XCPointerEventPath class not found for swizzling")
                    return
                }
                guard let pointerEventClass = NSClassFromString("XCPointerEvent") else {
                    print("Warning: XCPointerEventPath class not found for swizzling")
                    return
                }

                swizzleMethod(
                    class: pointerEventPathClass,
                    originalSelector: NSSelectorFromString("pressButton:atOffset:clickCount:"),
                    swizzledSelector: #selector(swizzled_pressButton)
                )

                swizzleMethod(
                    class: pointerEventPathClass,
                    originalSelector: NSSelectorFromString("releaseButton:atOffset:clickCount:"),
                    swizzledSelector: #selector(swizzled_releaseButton)
                )

                swizzleMethod(
                    class: pointerEventClass,
                    originalSelector: NSSelectorFromString("setKey:"),
                    swizzledSelector: #selector(swizzled_setKey)
                )
            }()

            /// Helper method to perform method swizzling
            /// - Parameters:
            ///   - class: The class containing the method to swizzle
            ///   - originalSelector: The original method selector
            ///   - swizzledSelector: The replacement method selector
            private static func swizzleMethod(class: AnyClass, originalSelector: Selector, swizzledSelector: Selector) {
                guard let originalMethod = class_getInstanceMethod(`class`, originalSelector),
                      var swizzledMethod = class_getInstanceMethod(UITestCase.self, swizzledSelector) else {
                    print("Warning: Could not find methods for swizzling \(originalSelector) and \(swizzledSelector)")
                    return
                }

                let didAddMethod = class_addMethod(
                    `class`,
                    swizzledSelector,
                    method_getImplementation(swizzledMethod),
                    method_getTypeEncoding(swizzledMethod)
                )

                if didAddMethod {
                    swizzledMethod = class_getInstanceMethod(`class`, swizzledSelector)!
                }
                method_exchangeImplementations(originalMethod, swizzledMethod)
            }
        }

        // Accessing the static property ensures the closure runs exactly once
        _ = OnceToken.token
    }

}

// MARK: - XCPointerEventPath Swizzled Methods

extension UITestCase {

    @TaskLocal static var shouldReplaceButtonWithMiddleMouseButton: Bool = false
    @TaskLocal static var keyEventOverride: (keyCode: Int, phase: UInt)?

    /// Swizzled implementation of [XCPointerEventPath pressButton:atOffset:clickCount:]
    /// Calls original implementation after optionally modifying button parameter allowing to simulate middle-click.
    @objc dynamic private func swizzled_pressButton(_ button: UInt64, at offset: Double, clickCount: UInt64) {
        var button = button
        if Self.shouldReplaceButtonWithMiddleMouseButton {
            button = 3
        }
        // Call the original
        self.swizzled_pressButton(button, at: offset, clickCount: clickCount)
    }

    /// Swizzled implementation of [XCPointerEventPath releaseButton:atOffset:clickCount:]
    /// Calls original implementation after optionally modifying button parameter allowing to simulate middle-click.
    @objc dynamic private func swizzled_releaseButton(_ button: UInt64, at offset: Double, clickCount: UInt64) {
        var button = button
        if Self.shouldReplaceButtonWithMiddleMouseButton {
            button = 3
        }
        // Call the original
        self.swizzled_releaseButton(button, at: offset, clickCount: clickCount)
    }

    /// Swizzled implementation of [XCPointerEvent setKey:]
    /// When keyEventOverride is set, manually configures the event with proper key code and phase (keyDown/keyUp).
    /// Otherwise calls original implementation.
    @objc dynamic private func swizzled_setKey(_ key: String) {
        if let keyEvent = Self.keyEventOverride {
            self.setEventType(0xb)
            self.setKeyCode(keyEvent.keyCode)
            self.setKeyPhase(keyEvent.phase)
            self.keyModifierFlags = (XCUIDevice.activeKeyModifiers ?? []).toNSEventModifierFlags()
            Logger.log("[\(self) setKey: \(key) keyCode: \(keyEvent.keyCode) phase: \(keyEvent.phase) modifierFlags: \(self.keyModifierFlags)]")
            return
        }

        // Call the original
        self.swizzled_setKey(key)
    }
    // XCPointerEvent private method definitions to use from swizzled_setKey
    @objc private dynamic func setEventType(_: UInt) {}
    @objc private dynamic func setKeyCode(_: Int) {}
    @objc private dynamic func setKeyPhase(_: UInt) {}
    @objc private dynamic var keyModifierFlags: NSEvent.ModifierFlags {
        get { [] }
        set {}
    }

    static func log(_ message: String) {
        Logger.log(message)
    }

    // MARK: - File Management Methods

    /// Track a file path for cleanup after the test completes.
    /// 
    /// UI tests run in a sandboxed environment and cannot directly read or delete files
    /// from user directories using standard FileManager calls. This method tracks files
    /// for automatic cleanup via the local test server in tearDown().
    /// 
    /// - Parameter path: The absolute file path to track for cleanup
    func trackForCleanup(_ path: String) {
        cleanupPaths.insert(path)
    }

    /// Read a file via the local test server to bypass permission issues.
    /// 
    /// This is required because UI tests run in a sandboxed environment and cannot
    /// directly read files from user directories using standard FileManager calls.
    /// The local test server provides a proxy that can read files on behalf of the test.
    /// 
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

        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].standardizedFileURL.path
        let paths = cleanupPaths.filter {
            URL(fileURLWithPath: $0).standardizedFileURL.path != downloadsDir
        }
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
    private static let logger = os.Logger()

    /// Log a debug message using XCTest's private debug log handler
    /// - Parameter message: The message to log
    static func log(_ message: String) {
        let currentContextSelector = NSSelectorFromString("currentContext")
        let logFormatSelector = NSSelectorFromString("_recordActivityMessageWithFormat:")

        guard let context = XCTContext.perform(currentContextSelector)?.takeUnretainedValue() else {
            fatalError("Could not retrieve current XCTContext")
        }
        if context.responds(to: logFormatSelector) {
            // Escape any %-escaped values in the message before passing it as the format string
            let escapedMessage = message.replacingOccurrences(of: "%", with: "%%")
            _ = context.perform(logFormatSelector, with: escapedMessage)
        }

        logger.log(level: .info, "\(message)")
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
