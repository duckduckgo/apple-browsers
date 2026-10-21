//
//  AtbIntegrationTests.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import Dispatch
import Foundation
import Swifter
import XCTest

class AtbIntegrationTests: XCTestCase {

    struct Constants {
        static let defaultTimeout: Double = 30
        static let serverHost = "127.0.0.1"
        static let atbResponse: [String: Any] = [
            "majorVersion": 77,
            "for_more_info": "https://duck.co/help/privacy/atb",
            "version": "v77-5",
            "minorVersion": 5
        ]
        static let activityTypeParam = "at"
        static let appUsageActivityType = "app_use"
        static let atbParam = "atb"
        static let setAtbParam = "set_atb"
    }

    let app = XCUIApplication()
    let server = HttpServer()
    private let requestRecorder = RequestRecorder()
    private var requestExpectation: XCTestExpectation!
    private var requestExpectationDescription = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        if ProcessInfo.processInfo.environment["INTERNAL_USER_MODE"] == "true" {
            app.launchArguments += ["-isInternalUser", "true"]
        }

        addRequestHandlers()

        // Swifter defaults to background QoS, which can leave localhost requests unanswered
        // during busy CI app launches.
        try server.start(0, forceIPv4: true, priority: .userInitiated)
        let baseURL = "http://\(Constants.serverHost):\(try server.port())"
        app.launchEnvironment = [
            "BASE_URL": baseURL,
            "PIXEL_BASE_URL": baseURL,
            "ONBOARDING": "false",
            // usually just has to match an existing variant to prevent one being allocated
            "VARIANT": "sc"
        ]

        resetExpectedRequestsForLaunch()
        app.launch()
    }

    override func tearDown() {
        super.tearDown()
        server.stop()
    }

    func testAppUsageCausesAtbRequests() {
        waitForRequests()
    }

    func testSearchCausesAtbRequests() {
        waitForRequests()
        resetExpectedRequestsForSearch()
        search(forText: "lemons")
        waitForRequests()
    }

    func testRelaunchCausesAtbRequests() {
        waitForRequests()
        resetExpectedRequestsForRelaunch()
        backgroundRelaunch()
        waitForRequests()
    }

    func backgroundRelaunch() {
        XCUIDevice.shared.press(.home)
        app.activate()
        if !app.descendants(matching: .any)["searchEntry"].waitForExistence(timeout: Constants.defaultTimeout) {
            fatalError("Can not find search field. Has the app launched?")
        }
    }

    private func search(forText text: String) {

        // Match by identifier across any element type: the omnibar's field can be
        // reported as a search field or a plain text field depending on its editing
        // state, and a type-specific query (e.g. `searchFields`) intermittently fails
        // to resolve it while the omnibar is transitioning.
        let searchentrySearchField = app.descendants(matching: .any)["searchEntry"]
        focus(searchentrySearchField)
        searchentrySearchField.typeText("\(text)\r")
        Snapshot.waitForLoadingIndicatorToDisappear(within: Constants.defaultTimeout)

    }

    /// Focuses the omnibar by tapping it.
    ///
    /// `hasKeyboardFocus` is intentionally not asserted: the omnibar's search field
    /// never reports keyboard focus to XCUITest even while it is actively being
    /// edited (the real first responder is a separate overlaid text view), so gating
    /// on it makes `focus` fail every time. We also can't gate on existence alone —
    /// the identifier appears before the omnibar finishes laying out, so the element
    /// can exist while it is not yet tappable. Wait for it to become *hittable* (the
    /// predicate re-evaluates over time, and also covers existence) before tapping,
    /// and let the subsequent `typeText` surface any real focus failure.
    private func focus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let isHittable = NSPredicate(format: "isHittable == true")

        for _ in 0..<3 {
            let hittableExpectation = XCTNSPredicateExpectation(predicate: isHittable, object: element)
            if XCTWaiter.wait(for: [hittableExpectation], timeout: Constants.defaultTimeout) == .completed {
                element.tap()
                return
            }
        }

        XCTFail("Could not focus \(element)", file: file, line: line)
    }

    /// We don't care which requests, as long as it's one of the expected endpoints.  The actual logic is tested in
    ///  the StatisticsLoader tests
    private func waitForRequests(
        timeout: TimeInterval = Constants.defaultTimeout,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = XCTWaiter.wait(for: [requestExpectation], timeout: timeout)
        guard result == .completed else {
            XCTFail(
                "No \(requestExpectationDescription) detected. \(requestRecorder.diagnostics)",
                file: file,
                line: line
            )
            return
        }
    }

    private func resetExpectedRequestsForLaunch() {
        resetExpectedRequests(description: "launch ATB completion") { request in
            let isInstallStatisticsRequest = request.path == "/exti/"
            let isAppUsageRequest = request.path == "/atb.js"
                && request.queryParam(Constants.activityTypeParam) == Constants.appUsageActivityType

            return isInstallStatisticsRequest || isAppUsageRequest
        }
    }

    private func resetExpectedRequestsForSearch() {
        resetExpectedRequests(description: "search ATB request") { request in
            guard request.path == "/atb.js" else {
                return false
            }

            return request.queryParam(Constants.atbParam) != nil
                && request.queryParam(Constants.setAtbParam) != nil
                && request.queryParam(Constants.activityTypeParam) == nil
        }
    }

    private func resetExpectedRequestsForRelaunch() {
        resetExpectedRequests(description: "relaunch ATB request") { request in
            request.path == "/atb.js"
                && request.queryParam(Constants.activityTypeParam) == Constants.appUsageActivityType
        }
    }

    private func resetExpectedRequests(description: String, matching matcher: @escaping (HttpRequest) -> Bool) {
        requestExpectationDescription = description
        requestExpectation = requestRecorder.reset(description: description, matching: matcher)
    }

    private func addRequestHandlers() {
        server["/exti/"] = { [requestRecorder] request in
            requestRecorder.recordExpectedRequest(request)
            return .accepted
        }

        server["/atb.js"] = { [requestRecorder] request in
            requestRecorder.recordExpectedRequest(request)
            return .ok(.json(Constants.atbResponse))
        }

        server["/t/:pixelName"] = { _ in
            return .accepted
        }

        server["/"] = { _ in
            return .ok(.html(""))
        }

        server.notFoundHandler = { [requestRecorder] request in
            requestRecorder.recordUnexpectedRequest(request)
            return .notFound
        }
    }
}

private final class RequestRecorder {

    private let lock = NSLock()
    private var handledRequests = [String]()
    private var unexpectedRequests = [String]()
    private var expectation: XCTestExpectation?
    private var requestMatcher: ((HttpRequest) -> Bool)?

    var diagnostics: String {
        lock.lock()
        defer { lock.unlock() }

        let handledRequestsDescription = description(for: handledRequests)
        let unexpectedRequestsDescription = description(for: unexpectedRequests)
        return """
        Handled ATB endpoint requests: \(handledRequestsDescription). \
        Unexpected requests: \(unexpectedRequestsDescription).
        """
    }

    func reset(description: String, matching matcher: @escaping (HttpRequest) -> Bool) -> XCTestExpectation {
        lock.lock()
        defer { lock.unlock() }

        handledRequests.removeAll()
        unexpectedRequests.removeAll()
        let expectation = XCTestExpectation(description: description)
        self.expectation = expectation
        requestMatcher = matcher
        return expectation
    }

    func recordExpectedRequest(_ request: HttpRequest) {
        record(request, in: \.handledRequests, fulfillsExpectation: true)
    }

    func recordUnexpectedRequest(_ request: HttpRequest) {
        record(request, in: \.unexpectedRequests, fulfillsExpectation: false)
    }

    private func record(
        _ request: HttpRequest,
        in keyPath: ReferenceWritableKeyPath<RequestRecorder, [String]>,
        fulfillsExpectation: Bool
    ) {
        let requestDescription = Self.description(for: request)
        let expectationToFulfill: XCTestExpectation?

        lock.lock()
        self[keyPath: keyPath].append(requestDescription)
        if fulfillsExpectation && requestMatcher?(request) == true {
            expectationToFulfill = expectation
            expectation = nil
        } else {
            expectationToFulfill = nil
        }
        lock.unlock()

        expectationToFulfill?.fulfill()
    }

    private static func description(for request: HttpRequest) -> String {
        guard !request.queryParams.isEmpty else {
            return request.path
        }

        let query = request.queryParams.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        return "\(request.path)?\(query)"
    }

    private func description(for requests: [String]) -> String {
        requests.isEmpty ? "none" : requests.joined(separator: ", ")
    }
}

private extension HttpRequest {

    func queryParam(_ named: String) -> String? {
        return queryParams.first(where: { $0.0 == named })?.1
    }
}
