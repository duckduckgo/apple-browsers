//
//  PrintingSubfeatureTests.swift
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

#if os(macOS)
import Navigation
#endif
import WebKit
import XCTest
@testable import BrowserServicesKit
@testable import UserScript

final class PrintingSubfeatureTests: XCTestCase {

    var printingSubfeature: PrintingSubfeature!
    var mockDelegate: MockPrintingSubfeatureDelegate!

    override func setUp() {
        super.setUp()
        printingSubfeature = PrintingSubfeature()
        mockDelegate = MockPrintingSubfeatureDelegate()
        printingSubfeature.delegate = mockDelegate
    }

    override func tearDown() {
        printingSubfeature = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Feature Name Tests

    func testFeatureNameValue() {
        XCTAssertEqual(PrintingSubfeature.featureNameValue, "print")
    }

    func testFeatureNameMatchesStaticValue() {
        XCTAssertEqual(printingSubfeature.featureName, PrintingSubfeature.featureNameValue)
    }

    // MARK: - Message Origin Policy Tests

    func testMessageOriginPolicyIsAll() {
        // Printing should work on any website
        switch printingSubfeature.messageOriginPolicy {
        case .all:
            // Expected
            break
        case .only:
            XCTFail("Expected messageOriginPolicy to be .all for print feature")
        }
    }

    // MARK: - Handler Tests

    func testHandlerForPrintMethodReturnsHandler() {
        let handler = printingSubfeature.handler(forMethodNamed: "print")
        XCTAssertNotNil(handler, "Handler for 'print' method should not be nil")
    }

    func testHandlerForUnknownMethodReturnsNil() {
        let handler = printingSubfeature.handler(forMethodNamed: "unknownMethod")
        XCTAssertNil(handler, "Handler for unknown method should be nil")
    }

    func testHandlerForEmptyMethodReturnsNil() {
        let handler = printingSubfeature.handler(forMethodNamed: "")
        XCTAssertNil(handler, "Handler for empty method name should be nil")
    }

    // MARK: - Delegate Tests

    func testDelegateIsWeakReference() {
        var delegate: MockPrintingSubfeatureDelegate? = MockPrintingSubfeatureDelegate()
        printingSubfeature.delegate = delegate
        XCTAssertNotNil(printingSubfeature.delegate)

        delegate = nil
        XCTAssertNil(printingSubfeature.delegate, "Delegate should be nil after being deallocated")
    }

    // MARK: - Broker Tests

    func testBrokerIsWeakReference() {
        var broker: UserScriptMessageBroker? = UserScriptMessageBroker(context: "test")
        printingSubfeature.broker = broker
        XCTAssertNotNil(printingSubfeature.broker)

        broker = nil
        XCTAssertNil(printingSubfeature.broker, "Broker should be nil after being deallocated")
    }

    // MARK: - Integration Tests

    func testPrintingSubfeatureCanBeInitialized() {
        let subfeature = PrintingSubfeature()
        XCTAssertNotNil(subfeature)
        XCTAssertNil(subfeature.delegate)
        XCTAssertNil(subfeature.broker)
    }

    func testWithBrokerSetsBrokerProperty() {
        let broker = UserScriptMessageBroker(context: "test")
        printingSubfeature.with(broker: broker)
        XCTAssertNotNil(printingSubfeature.broker)
    }

    // MARK: - Handler Invocation Tests

    @MainActor
    func testHandlerCallsDelegateWhenInvoked() async throws {
        // GIVEN
        let handler = printingSubfeature.handler(forMethodNamed: "print")
        XCTAssertNotNil(handler)

        let mockMessage = MockWKScriptMessage(name: "print", body: [:])

        // WHEN
        _ = try await handler!([:], mockMessage)

        // THEN
        XCTAssertTrue(mockDelegate.didRequestPrintCalled, "Delegate should be called when print handler is invoked")
    }

    @MainActor
    func testHandlerPassesWebViewToDelegate() async throws {
        // GIVEN
        let handler = printingSubfeature.handler(forMethodNamed: "print")
        let webView = WKWebView()
        let mockMessage = MockWKScriptMessage(name: "print", body: [:], webView: webView)

        // WHEN
        _ = try await handler!([:], mockMessage)

        // THEN
        XCTAssertTrue(mockDelegate.didRequestPrintCalled)
        XCTAssertEqual(mockDelegate.receivedWebView, webView, "Delegate should receive the webView from the message")
    }
}

// MARK: - Mock Delegate

class MockPrintingSubfeatureDelegate: PrintingSubfeatureDelegate {
    var didRequestPrintCalled = false
    var receivedFrameHandle: Any?
    var receivedWebView: WKWebView?

    @MainActor
    func printingSubfeatureDidRequestPrint(for frameHandle: Any?, in webView: WKWebView?) {
        didRequestPrintCalled = true
        receivedFrameHandle = frameHandle
        receivedWebView = webView
    }
}
