//
//  FormBrowserToolsTests.swift
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

import AIChat
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// The form tools against a stub page. Tab 0 is the chat, tab 1 the user's own, tab 2 one this chat opened.
@MainActor
final class FormBrowserToolsTests: XCTestCase {

    private var openedTabs: BrowserToolOpenedTabs!
    private var manager: WindowControllersManagerMock!
    private var tabs: [Tab]!
    private var driver: StubFormDriver!
    private var settler: StubPageSettler!
    private var context: BrowserToolCallContext!

    override func setUp() {
        super.setUp()
        openedTabs = BrowserToolOpenedTabs()
        driver = StubFormDriver()
        settler = StubPageSettler()
        tabs = ["https://duck.ai/", "https://user.example", "https://quotes.example/movers"].map {
            Tab(content: .url(URL(string: $0)!, credential: nil, source: .ui))
        }
        let collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs.map { .loaded($0) }),
                                                pinnedTabsManagerProvider: nil,
                                                burnerMode: .regular)
        manager = WindowControllersManagerMock()
        manager.customAllTabCollectionViewModels = [collection]
        context = BrowserToolCallContext(ownerTabID: tabs[0].uuid,
                                         ownerWindowToken: AIChatTabPickerSource.windowToken(forCollection: collection),
                                         isBurner: false,
                                         supportsElicitationForm: true)
        openedTabs.add(tabs[2].uuid, ownerTabID: tabs[0].uuid)
        driver.pages = [Self.quotePage()]
    }

    override func tearDown() {
        openedTabs = nil
        manager = nil
        tabs = nil
        driver = nil
        settler = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Scope

    func testWhenTheTabIsTheUsersOwnThenEveryFormToolAnswersNotFound() async {
        for tool in allTools() {
            let result = await tool.execute(arguments: arguments(tabID: tabs[1].uuid), context: context)
            XCTAssertEqual(result, .failure(.notFound), tool.name)
        }
        XCTAssertTrue(driver.calls.isEmpty)
    }

    func testWhenAnotherChatOpenedTheTabThenEveryFormToolAnswersNotFound() async {
        let otherChat = BrowserToolCallContext(ownerTabID: "other-chat", ownerWindowToken: context.ownerWindowToken,
                                               isBurner: false, supportsElicitationForm: true)

        for tool in allTools() {
            let result = await tool.execute(arguments: arguments(tabID: tabs[2].uuid), context: otherChat)
            XCTAssertEqual(result, .failure(.notFound), tool.name)
        }
        XCTAssertTrue(driver.calls.isEmpty)
    }

    func testWhenTheWindowIsAFireWindowThenEveryFormToolIsUnavailable() async {
        let fire = BrowserToolCallContext(ownerTabID: context.ownerTabID, ownerWindowToken: context.ownerWindowToken,
                                          isBurner: true, supportsElicitationForm: true)

        for tool in allTools() {
            let result = await tool.execute(arguments: arguments(tabID: tabs[2].uuid), context: fire)
            XCTAssertEqual(result, .failure(.unavailable), tool.name)
        }
        XCTAssertTrue(driver.calls.isEmpty)
    }

    func testWhenTheTabIdIsMissingThenTheArgumentsAreInvalid() async {
        for tool in allTools() {
            let result = await tool.execute(arguments: [:], context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), tool.name)
        }
    }

    // MARK: - getPageSnapshot

    func testWhenSnapshottingADuckAITabThenItsFormsAreDescribed() async throws {
        let result = await GetPageSnapshotBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver)
            .execute(arguments: ["tabId": .string(tabs[2].uuid)], context: context)

        let snapshot = try XCTUnwrap(result.successPayload)
        XCTAssertEqual(snapshot["tabId"], .string(tabs[2].uuid))
        XCTAssertEqual(snapshot["forms"]?.arrayValue?.first?["fields"]?.arrayValue?.count, 5)
        XCTAssertEqual(driver.calls, ["page"])
    }

    func testWhenThePageCannotBeReadThenTheSnapshotIsUnavailable() async {
        driver.pages = []

        let result = await GetPageSnapshotBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver)
            .execute(arguments: ["tabId": .string(tabs[2].uuid)], context: context)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    func testWhenDescribedThenTheSnapshotToolIsAutoAndReadOnly() {
        let tool = GetPageSnapshotBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver)

        XCTAssertEqual(tool.name, "getPageSnapshot")
        XCTAssertEqual(tool.permissionMode, .auto)
        XCTAssertEqual(tool.annotations?.readOnlyHint, true)
    }

    // MARK: -

    private func allTools() -> [any BrowserTool] {
        [GetPageSnapshotBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver)]
    }

    private func arguments(tabID: String) -> JSONValue {
        ["tabId": .string(tabID), "ref": "b1", "formRef": "f1", "fields": [["ref": "e1", "value": "Pat"]]]
    }

    /// e1 name, e2 home size, e3 phone with an error, e4/e5 a radio group, e6 password; b1 Next, b2 submit.
    static func quotePage(name: String = "", phoneError: String = "", url: String = "https://quotes.example/movers") -> BrowserToolRawPage {
        typealias Field = BrowserToolRawPage.Field
        typealias Labels = BrowserToolRawPage.Labels
        return BrowserToolRawPage(
            url: url,
            title: "Free Moving Quote | Example Movers",
            forms: [.init(ref: "f1", name: "moving-quote"), .init(ref: "f2", isPage: true)],
            fields: [
                Field(ref: "e1", formRef: "f1", name: "fullName", labels: Labels(labelFor: "Full name"), value: name),
                Field(ref: "e2", formRef: "f1", tag: "select", type: "select", labels: Labels(labelFor: "Home size"), value: "",
                      options: [.init(value: "", label: "Choose…"), .init(value: "2br", label: "2 bedrooms")]),
                Field(ref: "e3", formRef: "f1", type: "tel", labels: Labels(labelFor: "Phone"), error: phoneError, value: ""),
                Field(ref: "e4", formRef: "f1", type: "radio", name: "ownership", labels: Labels(wrapping: "I own"), value: "own",
                      checked: false, groupLabels: .init(nearby: "Do you own or rent?")),
                Field(ref: "e5", formRef: "f1", type: "radio", name: "ownership", labels: Labels(wrapping: "I rent"), value: "rent",
                      checked: false, groupLabels: .init(nearby: "Do you own or rent?")),
                Field(ref: "e6", formRef: "f1", type: "password", autocomplete: "new-password", labels: Labels(labelFor: "Password"))
            ],
            buttons: [
                .init(ref: "b1", formRef: "f1", typeAttribute: "button", text: "Next"),
                .init(ref: "b2", formRef: "f1", typeAttribute: "submit", text: "Get my quote")
            ])
    }
}

/// Serves `pages` one call at a time, repeating the last one, and records every call.
@MainActor
final class StubFormDriver: BrowserToolFormDriving {
    var pages: [BrowserToolRawPage] = []
    var readback: [BrowserToolFillReadback]?
    var clickSucceeds = true
    var submitSucceeds = true
    private(set) var calls: [String] = []
    private(set) var appliedActions: [BrowserToolFillAction] = []
    private(set) var submittedWith: (formRef: String, submitterRef: String?)?

    func page(in webView: WKWebView) async -> BrowserToolRawPage? {
        calls.append("page")
        guard !pages.isEmpty else { return nil }
        return pages.count > 1 ? pages.removeFirst() : pages[0]
    }

    func apply(_ actions: [BrowserToolFillAction], in webView: WKWebView) async -> [BrowserToolFillReadback]? {
        calls.append("apply")
        appliedActions = actions
        return readback ?? actions.map { action in
            switch action {
            case .text(let ref, let value), .select(let ref, let value):
                BrowserToolFillReadback(ref: ref, found: true, value: value, checked: nil)
            case .check(let ref, let checked):
                BrowserToolFillReadback(ref: ref, found: true, value: "on", checked: checked)
            }
        }
    }

    func click(_ ref: String, in webView: WKWebView) async -> Bool {
        calls.append("click \(ref)")
        return clickSucceeds
    }

    func submit(formRef: String, submitterRef: String?, in webView: WKWebView) async -> Bool {
        calls.append("submit \(formRef)")
        submittedWith = (formRef, submitterRef)
        return submitSucceeds
    }

    func millisecondsSinceLastChange(in webView: WKWebView) async -> Int? {
        0
    }
}

@MainActor
final class StubPageSettler: BrowserToolPageSettling {
    var navigated = false
    var suspendsUntilCancelled = false
    private(set) var settles: [(quietPeriod: TimeInterval, timeout: TimeInterval)] = []

    func settle(_ tab: Tab, from startURL: URL?, quietPeriod: TimeInterval, timeout: TimeInterval) async throws -> Bool {
        settles.append((quietPeriod, timeout))
        if suspendsUntilCancelled {
            try await Task.sleep(nanoseconds: 60 * NSEC_PER_SEC)
        }
        return navigated
    }
}
