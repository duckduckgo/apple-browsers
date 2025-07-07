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
import Foundation
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@objc(TestRunHelper)
final class TestRunHelper: NSObject {
    @objc(sharedInstance) static let shared = TestRunHelper()
    private var windowObserver: Any?

    fileprivate let processPool = WKProcessPool()

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)

        // allow mocking NSApp.currentEvent
        _=NSApplication.swizzleCurrentEventOnce

        // swizzle WKWebViewConfiguration.init to use a shared process pool
        _=WKWebViewConfiguration.swizzleInitOnce

        // dedicate temporary directory for tests
        _=FileManager.swizzleTemporaryDirectoryOnce
        FileManager.default.cleanupTemporaryDirectory()

        // provide extra info on failures
        _=NSError.swizzleLocalizedDescriptionOnce

        // add code to be run on Unit Tests startup here...

    }

}

extension TestRunHelper: XCTestObservation {

    func testBundleWillStart(_ testBundle: Bundle) {
        if AppVersion.runType == .unitTests {
            windowObserver = NotificationCenter.default.addObserver(forName: .init("NSWindowDidOrderOnScreenAndFinishAnimatingNotification"), object: nil, queue: .main) {_ in
                fatalError("Unit Tests should not present UI. Use MockWindow if needed.")
            }
        }

        if #available(macOS 13.0, *) {
            WKProcessPool._setWebProcessCountLimit(20)
        }
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
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
        if case .unitTests = AppVersion.runType {
            // cleanup dedicated temporary directory before each test run
            FileManager.default.cleanupTemporaryDirectory()
            NSAnimationContext.current.duration = 0
        }
        NSApp.swizzled_currentEvent = nil
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        if case .unitTests = AppVersion.runType {
            // cleanup dedicated temporary directory after each test run
            FileManager.default.cleanupTemporaryDirectory()
        }
        NSApp.swizzled_currentEvent = nil
        if #available(macOS 12.0, *) {
            WKWebView.customHandlerSchemes = []
        }
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
