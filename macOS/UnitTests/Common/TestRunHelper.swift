//
//  TestRunHelper.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Common
import CommonObjCExtensions
import Foundation
import os.log
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

private final class Expectation: XCTestExpectation, @unchecked Sendable {
    private(set) var isFulfilled = false
    override func fulfill() {
        isFulfilled = true
        super.fulfill()
    }
}

extension XCTestCase {

    var allowedNonNilVariables: Set<String> { [] }

    fileprivate func deallocExpectations() -> [XCTestExpectation] {
        TestRunHelper.shared.loadedViews.compactMap { [testName=name] ref in
            var objToDeinit: NSObject!
            guard let view = ref.view else { return nil }

            autoreleasepool {
                if view.window?.className.contains("NSMenu") == true
                    || view.nextResponder?.className.contains("NSMenuBar") == true
                    || view.window?.className.contains("TUINSWindow") == true {

                    objToDeinit = nil

                } else if !(view is WKWebView),
                          let viewController = view.nextResponder as? NSViewController,
                          !viewController.className.hasPrefix("TUINS"),
                          !viewController.className.hasPrefix("NSTextInsertionIndicator"),
                          !viewController.className.hasPrefix("STWeb"),
                          !viewController.className.hasPrefix("SPCompletionList") {

                    objToDeinit = viewController
                } else if view.window != nil {
                    objToDeinit = view
                }
            }
            guard let objToDeinit else { return nil }

            let descr = autoreleasepool {
                objToDeinit.description
            }
            let e = Expectation(description: "\(testName) deallocation of \(descr)")
            objToDeinit.onDeinit {
                Logger.tests.debug("\(testName) \(descr) deallocated")
                e.fulfill()
                if !e.isFulfilled {
                    XCTFail("\(descr) deallocated after timeout")
                }
            }
            return e
        }
    }

}

@objc(TestRunHelper)
final class TestRunHelper: NSObject {
    @objc(sharedInstance) static let shared = TestRunHelper()
    private var windowObserver: Any?

    fileprivate let processPool = WKProcessPool()
    fileprivate struct ViewRef {
        weak var view: NSView?
    }

    fileprivate var loadedViews: [ViewRef] = []
    fileprivate var nonNilVarsStoppedTestCases = Set<ObjectIdentifier>()

    @objc static var allowAppSendUserEvents: Bool = false

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)

        // allow mocking NSApp.currentEvent
        _=NSApplication.swizzleCurrentEventOnce

        // enable autorelease tracking for debugging
        NSObject.perform(NSSelectorFromString("enableAutoreleaseTracking"))

        // swizzle WKWebViewConfiguration.init to use a shared process pool
        _=WKWebViewConfiguration.swizzleInitOnce
        _=WKWebView.swizzleInstallScreenTimeWebpageControllerIfNeededOnce

        // swizzle NSView.init to track loaded views
        _=NSView.swizzleInitWithFrameOnce

        // dedicate temporary directory for tests
        _=FileManager.swizzleTemporaryDirectoryOnce
        FileManager.default.cleanupTemporaryDirectory()

        // provide extra info on failures
        _=NSError.swizzleLocalizedDescriptionOnce

        // add code to be run on Unit Tests startup here...

    }

    fileprivate func registerView(_ view: NSView) {
        loadedViews.append(.init(view: view))
    }

}

extension TestRunHelper: XCTestObservation {

    func testBundleWillStart(_ testBundle: Bundle) {
        UserDefaults.standard.set(false, forKey: "NSAutomaticWindowAnimationsEnabled")
        if AppVersion.runType == .unitTests {
            windowObserver = NotificationCenter.default.addObserver(forName: .init("NSWindowDidOrderOnScreenAndFinishAnimatingNotification"), object: nil, queue: .main) {_ in
                fatalError("Unit Tests should not present UI. Use MockWindow if needed.")
            }
        }

        if #available(macOS 13.0, *) {
            WKProcessPool._setWebProcessCountLimit(5)
        }
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        UserDefaults.standard.removeObject(forKey: "NSAutomaticWindowAnimationsEnabled")

        if case .integrationTests = AppVersion.runType {
            FileManager.default.cleanupTemporaryDirectory(excluding: ["Database.sqlite",
                                                                      "Database.sqlite-wal",
                                                                      "Database.sqlite-shm"])
        }
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {

    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {

    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        Self.allowAppSendUserEvents = false

        if !loadedViews.isEmpty {
            let descr = loadedViews.compactMap(\.view).description
            Logger.tests.warning("Loaded views not empty at start of test case: \(descr)")
            loadedViews = []
        }

        if case .unitTests = AppVersion.runType {
            // cleanup dedicated temporary directory before each test run
            FileManager.default.cleanupTemporaryDirectory()
            NSAnimationContext.current.duration = 0
        }
        NSApp.swizzled_currentEvent = nil
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        assert(!TestRunHelper.allowAppSendUserEvents, "allowAppSendUserEvents must be set to `false` in tearDown()")

        if case .unitTests = AppVersion.runType {
            // cleanup dedicated temporary directory after each test run
            FileManager.default.cleanupTemporaryDirectory()
        }
        NSApp.swizzled_currentEvent = nil
        if #available(macOS 12.0, *) {
            WKWebView.customHandlerSchemes = []
        }

        // Check for non-nil variables that should be cleaned up
#if !CI
        checkTestCaseVariables(testCase)
#endif

        if !TestRunHelper.shared.loadedViews.isEmpty {
            for ref in TestRunHelper.shared.loadedViews {
                (ref.view as? DuckDuckGo_Privacy_Browser.WebView)?.isLoadingObserver = nil
                // if the WebView never appears on the screen, `NSView._finalize` method is never called
                // and the notification observer keeps strong ref to the WebView
            }
            let descriptions = TestRunHelper.shared.loadedViews.compactMap(\.view?.description).joined(separator: ", ")
            let testName = testCase.name
            Logger.tests.debug("\(testName) tearDown: waiting for deallocation: \(descriptions)")

            class WaiterDelegate: NSObject, XCTWaiterDelegate {
                let callback: ([XCTestExpectation]) -> Void
                init(callback: @escaping ([XCTestExpectation]) -> Void) {
                    self.callback = callback
                }
                func waiter(_ waiter: XCTWaiter, didTimeoutWithUnfulfilledExpectations unfulfilledExpectations: [XCTestExpectation]) {
                    callback(unfulfilledExpectations)
                }
            }
            let waiter = WaiterDelegate { unfulfilledExpectations in
                testCase.reportIssue("""
                Test timed out waiting for deallocation: \(unfulfilledExpectations)"

                To exorcise the issue:
                  1. Wrap setUp and tearDown method contents in autoreleasepool {} to ensure proper cleanup
                  2. Make sure you‘re using MockWindow where possible and initialize variables in setUp method only
                  2. Enable MallocStackLogging in the Tests scheme for detailed stack traces in Memory Browser
                  3. Use AutoreleaseTracker with malloc stack trace option to debug retain cycles in Memory Browser (see NSObject+AutoreleaseTracking.m)
                  4. Check Memory Browser for retained objects after test completion
                  5. Consider adding autoreleasepool {} around heavy object creation in tests
                  6. Use Instruments > Allocations to track object lifecycle
                  7. Disable this check and add breakpoints in dealloc methods to verify cleanup timing
                  8. If the deallocation expectation of this class is incorrect, you can add it to exclusions in `deallocExpectations`
                """)
            }
            XCTWaiter(delegate: waiter).wait(for: testCase.deallocExpectations(), timeout: 5)

            withExtendedLifetime(waiter) {}
            TestRunHelper.shared.loadedViews = []

            loadedViews = []
        }
    }

    private func checkTestCaseVariables(_ testCase: XCTestCase) {
        let mirror = Mirror(reflecting: testCase)
        var nonNilVariables: [String] = []

        for child in mirror.children {
            guard let label = child.label,
                  !label.hasPrefix("_"), // Ignore private/system properties
                  !isSystemProperty(label) else { continue }

            if isValueNonNil(child.value) {
                nonNilVariables.append(label)
            }
        }

        let allowedNonNilVariables = testCase.allowedNonNilVariables
        let unexpectedNonNilVariables = Set(nonNilVariables).subtracting(allowedNonNilVariables)

        if !unexpectedNonNilVariables.isEmpty,
           // don't break twice
           nonNilVarsStoppedTestCases.insert(ObjectIdentifier(type(of: testCase))).inserted {
            testCase.reportIssue("""
            Test case '\(testCase.name)' has non-nil variables that should be nullified (or cleared - for Collections) after test completion: \(Array(unexpectedNonNilVariables).sorted())
            Reset the variables in `tearDown` method or override `allowedNonNilVariables` and add variable names to the returned value to allow
            the test to keep the variables after its completion.
            """)
        }
    }

    private func isSystemProperty(_ name: String) -> Bool {
        // List of known XCTestCase system properties to ignore
        let systemProperties: Set<String> = [
            "continueAfterFailure",
            "testRun",
            "allowedNonNilVariables" // Our own property
        ]
        return systemProperties.contains(name)
    }

    private func isValueNonNil(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)

        // Check if it's an Optional or non-empty collection
        if case .optional = mirror.displayStyle {
            if let firstChild = mirror.children.first {
                return isValueNonNil(firstChild.value)
            } else {
                return false
            }
        } else if [.collection, .dictionary, .set].contains(mirror.displayStyle) {
            return mirror.children.first != nil
        }

        // For non-optionals, we only care about reference types that could be cleaned up
        // Primitive types and value types can remain as they don't represent resources to clean up
        return mirror.displayStyle == .class
    }

}

extension NSApplication {

    // allow mocking NSApp.currentEvent

    static var swizzleCurrentEventOnce: Void = {
        let curentEventMethod = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.currentEvent))!
        let swizzledCurentEventMethod = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.swizzled_currentEvent))!

        method_exchangeImplementations(curentEventMethod, swizzledCurentEventMethod)
    }()

    private static let currentEventKey = UnsafeRawPointer(bitPattern: "currentEventKey".hashValue)!
    @objc dynamic var swizzled_currentEvent: NSEvent? {
        get {
            objc_getAssociatedObject(self, Self.currentEventKey) as? NSEvent
                ?? self.swizzled_currentEvent // call original
        }
        set {
            objc_setAssociatedObject(self, Self.currentEventKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

}

extension NSView {

    static var swizzleInitWithFrameOnce: Void = {
        let initMethod = class_getInstanceMethod(NSView.self, #selector(NSView.init(frame:)))!
        let swizzledInitMethod = class_getInstanceMethod(NSView.self, #selector(NSView.swizzled_initWithFrame))!

        method_exchangeImplementations(initMethod, swizzledInitMethod)
    }()

    @objc dynamic func swizzled_initWithFrame(frame: CGRect) -> NSView {
        let view = swizzled_initWithFrame(frame: frame)

        if let observer = view.value(forIvar: "_antialiasThresholdChangedNotificationObserver").map({ Unmanaged<AnyObject>.fromOpaque($0) })?.takeUnretainedValue() {
            NotificationCenter.default.removeObserver(observer)
        }
        if !(view.className.contains("NSMenu")
             || view.className.contains("NSNextStep")
             || view.className.hasPrefix("_")
             || (view.className.hasPrefix("WK") && !(view is WKWebView))
             || view.className.contains("NSTextView")) {

            TestRunHelper.shared.registerView(view)
        }

        return view
    }

}

extension WKWebViewConfiguration {

    static var swizzleInitOnce: Void = {
        let initMethod = class_getInstanceMethod(WKWebViewConfiguration.self, #selector(NSObject.init))!
        let swizzledInitMethod = class_getInstanceMethod(WKWebViewConfiguration.self, #selector(WKWebViewConfiguration.swizzled_init))!

        method_exchangeImplementations(initMethod, swizzledInitMethod)
    }()

    private static var processPoolInitArg: WKProcessPool?

    @objc dynamic func swizzled_init() -> WKWebViewConfiguration {
        let configuration = swizzled_init()
        if let processPool = Self.processPoolInitArg {
            configuration.processPool = processPool
        } else if case .unitTests = AppVersion.runType {
            configuration.processPool = TestRunHelper.shared.processPool
        }
        return configuration
    }

    convenience init(processPool: WKProcessPool) {
        Self.processPoolInitArg = processPool
        defer {
            Self.processPoolInitArg = nil
        }
        self.init()
    }

}
extension WKWebView {
    static var swizzleInstallScreenTimeWebpageControllerIfNeededOnce: Void = {
        guard let originalMethod = class_getInstanceMethod(WKWebView.self, NSSelectorFromString("_installScreenTimeWebpageControllerIfNeeded")) else { return }
        let swizzledMethod = class_getInstanceMethod(WKWebView.self, #selector(swizzled_installScreenTimeWebpageControllerIfNeeded))!

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    // skip STWebRemoteViewController initialization
    @objc dynamic func swizzled_installScreenTimeWebpageControllerIfNeeded() {
    }
}
