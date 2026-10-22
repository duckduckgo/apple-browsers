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
    private var collection: TabCollectionViewModel!
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
        collection = TabCollectionViewModel(tabCollection: TabCollection(tabs: tabs.map { .loaded($0) }),
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
        collection = nil
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

    // MARK: - fillForm

    func testWhenFillingThenValuesAreReadBackRefusedFieldsFailAloneAndErrorsAreReported() async throws {
        driver.pages = [Self.quotePage(), Self.quotePage(phoneError: "Enter a 10-digit US phone number.")]

        let result = await fillForm().execute(arguments: [
            "tabId": .string(tabs[2].uuid),
            "fields": [
                ["ref": "e1", "value": "Pat Doe"],
                ["ref": "e2", "value": "2 bedrooms"],
                ["ref": "e4", "value": "I rent"],
                ["ref": "e6", "value": "hunter2"],
                ["ref": "e3", "value": "12"]
            ]
        ], context: context)

        XCTAssertEqual(result, .success([
            "tabId": .string(tabs[2].uuid),
            "filled": [["ref": "e1", "value": "Pat Doe"], ["ref": "e2", "value": "2br"], ["ref": "e4", "value": "rent"], ["ref": "e3", "value": "12"]],
            "failed": [["ref": "e6", "error": "restricted"]],
            "errors": [["ref": "e3", "message": "Enter a 10-digit US phone number."]]
        ]))
        XCTAssertEqual(driver.appliedActions, [
            .text(ref: "e1", value: "Pat Doe"),
            .select(ref: "e2", value: "2br"),
            .check(ref: "e5", checked: true),
            .text(ref: "e3", value: "12")
        ])
        XCTAssertEqual(settler.settles.map { $0.timeout }, [FillFormBrowserTool.timeout])
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("submit") })
    }

    func testWhenFieldsAreMissingEmptyOrTooManyThenTheArgumentsAreInvalid() async {
        let tooMany: JSONValue = .array((0...FillFormBrowserTool.maxFields).map { _ in ["ref": "e1", "value": "x"] })
        let invalid: [JSONValue] = [[], tooMany, [["value": "x"]], [["ref": "e1", "value": 5]], [["ref": "", "value": "x"]], "e1"]

        for fields in invalid {
            let result = await fillForm().execute(arguments: ["tabId": .string(tabs[2].uuid), "fields": fields], context: context)
            XCTAssertEqual(result, .failure(.invalidArguments), "\(fields)")
        }
        XCTAssertFalse(driver.calls.contains("apply"))
    }

    func testWhenNothingCanBeFilledThenNothingIsAppliedAndTheFailuresAreReported() async throws {
        let result = await fillForm().execute(arguments: ["tabId": .string(tabs[2].uuid), "fields": [["ref": "e6", "value": "hunter2"], ["ref": "e42", "value": "x"]]],
                                              context: context)

        let payload = try XCTUnwrap(result.successPayload)
        XCTAssertEqual(payload["filled"], [])
        XCTAssertEqual(payload["failed"], [["ref": "e6", "error": "restricted"], ["ref": "e42", "error": "not_found"]])
        XCTAssertFalse(driver.calls.contains("apply"))
        XCTAssertTrue(settler.settles.isEmpty)
    }

    func testWhenFillingIsCancelledWhileThePageSettlesThenTheCallIsCancelled() async throws {
        settler.suspendsUntilCancelled = true

        let tool = fillForm()
        let arguments: JSONValue = ["tabId": .string(tabs[2].uuid), "fields": [["ref": "e1", "value": "Pat"]]]
        let call = Task { await tool.execute(arguments: arguments, context: context) }
        try await waitUntil { !self.settler.settles.isEmpty }
        call.cancel()

        let result = await call.value
        XCTAssertEqual(result, .failure(.cancelled))
    }

    // MARK: - clickElement

    func testWhenTheButtonIsASubmitThenTheClickIsRefusedWithoutClicking() async {
        let result = await clickElement().execute(arguments: ["tabId": .string(tabs[2].uuid), "ref": "b2"], context: context)

        XCTAssertEqual(result, .failure(.useSubmitForm))
        XCTAssertEqual(driver.calls, ["page"])
    }

    func testWhenClickingNextThenThePageAfterwardsIsReturnedWithItsErrors() async throws {
        driver.pages = [Self.quotePage(), Self.quotePage(phoneError: "This field is required.")]

        let result = await clickElement().execute(arguments: ["tabId": .string(tabs[2].uuid), "ref": "b1"], context: context)

        let payload = try XCTUnwrap(result.successPayload)
        XCTAssertEqual(payload["tabId"], .string(tabs[2].uuid))
        XCTAssertEqual(payload["url"], "https://quotes.example/movers")
        XCTAssertEqual(payload["title"], "Free Moving Quote | Example Movers")
        XCTAssertEqual(payload["navigated"], false)
        XCTAssertEqual(payload["errors"], [["ref": "e3", "message": "This field is required."]])
        XCTAssertEqual(payload["snapshot"]?["tabId"], .string(tabs[2].uuid))
        XCTAssertEqual(driver.calls, ["page", "click b1", "page"])
        XCTAssertEqual(settler.settles.map { $0.quietPeriod }, [ClickElementBrowserTool.quietPeriod])
    }

    func testWhenTheClickShowsNoErrorsAndNavigatesThenErrorsAreLeftOut() async throws {
        settler.navigated = true

        let result = await clickElement().execute(arguments: ["tabId": .string(tabs[2].uuid), "ref": "b1"], context: context)

        let payload = try XCTUnwrap(result.successPayload?.objectValue)
        XCTAssertNil(payload["errors"])
        XCTAssertEqual(payload["navigated"], true)
    }

    func testWhenTheButtonIsUnknownThenItIsNotFound() async {
        let unknown = await clickElement().execute(arguments: ["tabId": .string(tabs[2].uuid), "ref": "b9"], context: context)
        let missing = await clickElement().execute(arguments: ["tabId": .string(tabs[2].uuid)], context: context)

        XCTAssertEqual(unknown, .failure(.notFound))
        XCTAssertEqual(missing, .failure(.invalidArguments))
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("click") })
    }

    // MARK: - submitForm

    func testWhenAskingToSubmitThenThePromptPreviewsWhatTheSiteWillReceive() async throws {
        var page = Self.quotePage(name: "Pat Doe")
        page.fields[1].value = "2br"
        page.fields[3].checked = true
        driver.pages = [page]

        let prompt = await submitForm().approvalPrompt(arguments: ["tabId": .string(tabs[2].uuid), "formRef": "f1"], context: context)

        XCTAssertEqual(prompt, .ask(message: "Duck.ai wants to submit a form on Example Movers.", meta: [
            "formPreview": [
                "site": "Example Movers",
                "url": "https://quotes.example/movers",
                "formName": "moving-quote",
                "fields": [
                    ["label": "Full name", "value": "Pat Doe"],
                    ["label": "Home size", "value": "2 bedrooms"],
                    ["label": "Do you own or rent?", "value": "I own"]
                ]
            ]
        ]))
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("submit") })
    }

    func testWhenThePageIsASignInPageThenTheSubmitIsRefusedBeforeAsking() async {
        driver.pages = [BrowserToolRawPage(url: "https://quotes.example/login", forms: [.init(ref: "f1")], fields: [
            .init(ref: "e1", formRef: "f1", type: "email"),
            .init(ref: "e2", formRef: "f1", type: "password")
        ])]

        let prompt = await submitForm().approvalPrompt(arguments: ["tabId": .string(tabs[2].uuid), "formRef": "f1"], context: context)
        let direct = await submitForm().execute(arguments: ["tabId": .string(tabs[2].uuid), "formRef": "f1"], context: context)

        XCTAssertEqual(prompt, .refuse(.restricted))
        XCTAssertEqual(direct, .failure(.restricted))
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("submit") })
    }

    func testWhenTheFormIsUnknownOrTheTabIsTheUsersThenTheSubmitIsRefusedBeforeAsking() async {
        let unknownForm = await submitForm().approvalPrompt(arguments: ["tabId": .string(tabs[2].uuid), "formRef": "f9"], context: context)
        let usersTab = await submitForm().approvalPrompt(arguments: ["tabId": .string(tabs[1].uuid), "formRef": "f1"], context: context)

        XCTAssertEqual(unknownForm, .refuse(.notFound))
        XCTAssertEqual(usersTab, .refuse(.notFound))
    }

    func testWhenSubmittedAndTheFormIsReplacedByAConfirmationThenItWasSubmitted() async throws {
        var confirmation = BrowserToolRawPage(url: "https://quotes.example/movers", title: "Quote request received | Example Movers")
        confirmation.messages = [.init(text: "Thanks, we received your request. Reference REF-12345.", isAlert: false)]
        driver.pages = [Self.quotePage(name: "Pat Doe"), confirmation]

        let result = await submitForm().execute(arguments: ["tabId": .string(tabs[2].uuid), "formRef": "f1"], context: context)

        XCTAssertEqual(result, .success([
            "tabId": .string(tabs[2].uuid),
            "url": "https://quotes.example/movers",
            "title": "Quote request received | Example Movers",
            "submitted": true,
            "confirmationText": "Thanks, we received your request. Reference REF-12345.",
            "errors": []
        ]))
        XCTAssertEqual(driver.submittedWith?.formRef, "f1")
        XCTAssertEqual(driver.submittedWith?.submitterRef, "b2")
        XCTAssertEqual(settler.settles.map { $0.timeout }, [SubmitFormBrowserTool.timeout])
    }

    func testWhenTheSiteRejectsTheSubmitThenItIsNotSubmittedAndItsErrorsAreReturned() async throws {
        driver.pages = [Self.quotePage(), Self.quotePage(phoneError: "Enter a 10-digit US phone number.")]

        let result = await submitForm().execute(arguments: ["tabId": .string(tabs[2].uuid), "formRef": "f1"], context: context)

        let payload = try XCTUnwrap(result.successPayload)
        XCTAssertEqual(payload["submitted"], false)
        XCTAssertEqual(payload["errors"], [["ref": "e3", "message": "Enter a 10-digit US phone number."]])
    }

    /// The path a real call takes: the invoker asks with the tool's preview, and only Once submits.
    func testWhenTheUserApprovesThePromptThenTheFormIsSubmittedAndWhenTheyDeclineItIsNot() async {
        let elicitations = AIChatElicitationCoordinator(timeout: 5)
        let invoker = makeInvoker(elicitations: elicitations)
        let arguments: JSONValue = ["tabId": .string(tabs[2].uuid), "formRef": "f1"]

        let declined = await invoker.invoke(toolNamed: "submitForm", arguments: arguments, context: context,
                                            elicitationPusher: AnsweringPusher(elicitations: elicitations, answer: MCPElicitationResult(action: .decline)))
        XCTAssertEqual(declined, .failure(.denied))
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("submit") })

        let pusher = AnsweringPusher(elicitations: elicitations, answer: MCPElicitationResult(action: .accept, content: ["choice": "allowOnce"]))
        _ = await invoker.invoke(toolNamed: "submitForm", arguments: arguments, context: context, elicitationPusher: pusher)
        XCTAssertTrue(driver.calls.contains("submit f1"))
        XCTAssertEqual(pusher.pushed?.requestedSchema, BrowserToolPermissionElicitation.allowOnceSchema)
        XCTAssertNotNil(pusher.pushed?.meta?["formPreview"])
    }

    func testWhenTheCallIsCancelledWhileTheUserDecidesThenThePromptIsDismissedAndNothingIsSubmitted() async throws {
        let elicitations = AIChatElicitationCoordinator(timeout: 5)
        let invoker = makeInvoker(elicitations: elicitations)
        let pusher = AnsweringPusher(elicitations: elicitations, answer: nil)
        let arguments: JSONValue = ["tabId": .string(tabs[2].uuid), "formRef": "f1"]

        let call = Task { await invoker.invoke(toolNamed: "submitForm", arguments: arguments, context: context, callID: "call-1", elicitationPusher: pusher) }
        try await waitUntil { !elicitations.pendingPrompts.isEmpty }
        invoker.cancelCall(callID: "call-1", ownerTabID: context.ownerTabID)

        let result = await call.value
        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertTrue(elicitations.pendingPrompts.isEmpty)
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("submit") })
    }

    func testWhenDescribedThenSubmitFormIsApprovedEachCallAndTheOthersAreAuto() {
        XCTAssertTrue(submitForm().approvesEachCall)
        XCTAssertEqual(submitForm().permissionMode, .ask)
        XCTAssertEqual(fillForm().permissionMode, .auto)
        XCTAssertEqual(clickElement().permissionMode, .auto)
        XCTAssertEqual(allTools().map { $0.name }, ["getPageSnapshot", "fillForm", "clickElement", "submitForm", "showTab"])
        XCTAssertEqual(showTab().permissionMode, .auto)
    }

    // MARK: - Checkout

    func testWhenSnapshottingACheckoutThenCardFieldsHaveNoValueAndTheTotalIsAnOutput() async throws {
        driver.pages = [Self.checkoutPage()]

        let result = await GetPageSnapshotBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver)
            .execute(arguments: ["tabId": .string(tabs[2].uuid)], context: context)

        let form = try XCTUnwrap(result.successPayload?["forms"]?.arrayValue?.first)
        let fields = try XCTUnwrap(form["fields"]?.arrayValue)
        XCTAssertEqual(form["hasPaymentFields"], true)
        XCTAssertEqual(fields.filter { $0["sensitive"] == "payment" }.map { $0["ref"] }, ["e2", "e3"])
        XCTAssertTrue(fields.filter { $0["sensitive"] == "payment" }.allSatisfy { $0["value"] == nil })
        XCTAssertEqual(fields.last, ["ref": "e4", "label": "Order total", "type": "output", "required": false, "autocomplete": "",
                                     "value": "$129.00", "readOnly": true])
    }

    func testWhenFillingTheCardFieldThenTheUserMustDoItAndTheOtherFieldsStillFill() async throws {
        driver.pages = [Self.checkoutPage()]

        let result = await fillForm().execute(arguments: [
            "tabId": .string(tabs[2].uuid),
            "fields": [["ref": "e1", "value": "Jamie"], ["ref": "e2", "value": "4242424242424242"]]
        ], context: context)

        let payload = try XCTUnwrap(result.successPayload)
        XCTAssertEqual(payload["failed"], [["ref": "e2", "error": "user_action_required"]])
        XCTAssertEqual(payload["filled"], [["ref": "e1", "value": "Jamie"]])
        XCTAssertEqual(driver.appliedActions, [.text(ref: "e1", value: "Jamie")])
    }

    func testWhenSubmittingACheckoutThenTheUserMustDoItAndNobodyIsAsked() async {
        driver.pages = [Self.checkoutPage()]
        let arguments: JSONValue = ["tabId": .string(tabs[2].uuid), "formRef": "f1"]

        let prompt = await submitForm().approvalPrompt(arguments: arguments, context: context)
        let direct = await submitForm().execute(arguments: arguments, context: context)

        XCTAssertEqual(prompt, .refuse(.userActionRequired))
        XCTAssertEqual(direct, .failure(.userActionRequired))
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("submit") })
    }

    func testWhenClickingPlaceOrderThenItIsRefusedEvenAsAPlainButton() async {
        driver.pages = [Self.checkoutPage()]

        let result = await clickElement().execute(arguments: ["tabId": .string(tabs[2].uuid), "ref": "b1"], context: context)

        XCTAssertEqual(result, .failure(.useSubmitForm))
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("click") })
    }

    func testWhenClickingAddToCartOnAProductFormThenItIsClicked() async throws {
        driver.pages = [BrowserToolRawPage(url: "https://shop.example/product", forms: [.init(ref: "f1")], fields: [
            .init(ref: "e1", formRef: "f1", tag: "select", type: "select", name: "size", value: "42"),
            .init(ref: "e2", formRef: "f1", type: "number", name: "quantity", value: "1")
        ], buttons: [.init(ref: "b1", formRef: "f1", typeAttribute: nil, inForm: true, text: "Add to cart")])]

        let result = await clickElement().execute(arguments: ["tabId": .string(tabs[2].uuid), "ref": "b1"], context: context)

        XCTAssertNotNil(result.successPayload)
        XCTAssertTrue(driver.calls.contains("click b1"))
    }

    // MARK: - showTab

    func testWhenShowingADuckAITabThenItIsSelected() async throws {
        let result = await showTab().execute(arguments: ["tabId": .string(tabs[2].uuid)], context: context)

        let payload = try XCTUnwrap(result.successPayload)
        XCTAssertEqual(payload["tabId"], .string(tabs[2].uuid))
        XCTAssertEqual(payload["shown"], true)
        XCTAssertTrue(collection.selectedTabViewModel?.tab === tabs[2])
        XCTAssertTrue(driver.calls.isEmpty)
    }

    /// With the card field focused, Autofill offers the user's saved card.
    func testWhenShowingWithAFocusRefThenThatElementIsFocused() async {
        driver.pages = [Self.checkoutPage()]

        _ = await showTab().execute(arguments: ["tabId": .string(tabs[2].uuid), "focusRef": "e2"], context: context)

        XCTAssertEqual(driver.calls, ["page", "focus e2"])
        XCTAssertTrue(collection.selectedTabViewModel?.tab === tabs[2])
    }

    func testWhenTheFocusRefIsUnknownThenNothingMoves() async {
        let unknown = await showTab().execute(arguments: ["tabId": .string(tabs[2].uuid), "focusRef": "e99"], context: context)
        let notText = await showTab().execute(arguments: ["tabId": .string(tabs[2].uuid), "focusRef": 5], context: context)

        XCTAssertEqual(unknown, .failure(.notFound))
        XCTAssertEqual(notText, .failure(.invalidArguments))
        XCTAssertTrue(collection.selectedTabViewModel?.tab === tabs[0])
        XCTAssertFalse(driver.calls.contains { $0.hasPrefix("focus") })
    }

    func testWhenShowingTheUsersOwnTabThenItIsNotFoundAndStaysInTheBackground() async {
        let result = await showTab().execute(arguments: ["tabId": .string(tabs[1].uuid)], context: context)

        XCTAssertEqual(result, .failure(.notFound))
        XCTAssertTrue(collection.selectedTabViewModel?.tab === tabs[0])
    }

    // MARK: -

    private func showTab() -> ShowTabBrowserTool {
        ShowTabBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver)
    }

    private func fillForm() -> FillFormBrowserTool {
        FillFormBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver, settler: settler)
    }

    private func clickElement() -> ClickElementBrowserTool {
        ClickElementBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver, settler: settler)
    }

    private func submitForm() -> SubmitFormBrowserTool {
        SubmitFormBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver, settler: settler)
    }

    private func allTools() -> [any BrowserTool] {
        [GetPageSnapshotBrowserTool(windowControllersManager: manager, openedTabs: openedTabs, driver: driver), fillForm(), clickElement(), submitForm(), showTab()]
    }

    private func makeInvoker(elicitations: AIChatElicitationCoordinator) -> BrowserToolInvoker {
        let configuration = FormToolsConfiguration()
        return BrowserToolInvoker(catalog: BrowserToolCatalog(tools: allTools(), configuration: configuration),
                                  configuration: configuration,
                                  permissions: FormToolsPermissions(),
                                  elicitations: elicitations,
                                  openedTabs: openedTabs)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }

    private func arguments(tabID: String) -> JSONValue {
        ["tabId": .string(tabID), "ref": "b1", "formRef": "f1", "fields": [["ref": "e1", "value": "Pat"]]]
    }

    /// e1 first name, e2 card number, e3 security code (classified by Autofill), e4 the total; b1 Place order.
    static func checkoutPage() -> BrowserToolRawPage {
        typealias Field = BrowserToolRawPage.Field
        typealias Labels = BrowserToolRawPage.Labels
        return BrowserToolRawPage(
            url: "https://shop.example/checkout",
            title: "Checkout | Example Shoes",
            forms: [.init(ref: "f1", name: "checkout")],
            fields: [
                Field(ref: "e1", formRef: "f1", name: "firstName", autocomplete: "given-name", labels: Labels(labelFor: "First name"), value: ""),
                Field(ref: "e2", formRef: "f1", name: "cc", autocomplete: "cc-number", labels: Labels(labelFor: "Card number")),
                Field(ref: "e3", formRef: "f1", name: "x", labels: Labels(labelFor: "Security code"), ddgInputType: "creditCards.cardSecurityCode"),
                Field(ref: "e4", formRef: "f1", tag: "output", type: "output", name: "total", labels: Labels(labelFor: "Order total"),
                      value: "$129.00", readOnly: true)
            ],
            buttons: [.init(ref: "b1", formRef: "f1", typeAttribute: "button", text: "Place order")])
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
    var focusSucceeds = true
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
                BrowserToolFillReadback(ref: ref, found: true, value: pages.first?.fields.first { $0.ref == ref }?.value ?? "on", checked: checked)
            }
        }
    }

    func click(_ ref: String, in webView: WKWebView) async -> Bool {
        calls.append("click \(ref)")
        return clickSucceeds
    }

    func focus(_ ref: String, in webView: WKWebView) async -> Bool {
        calls.append("focus \(ref)")
        return focusSucceeds
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

private final class FormToolsConfiguration: BrowserToolsConfiguration {
    let isEnabled = true
    func isToolEnabled(named name: String) -> Bool { true }
}

private final class FormToolsPermissions: BrowserToolPermissionStoring {
    let storedDecisions: [String: BrowserToolPermissionState] = [:]
    func state(forToolNamed name: String) -> BrowserToolPermissionState { .ask }
    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String) {}
    func clearAll() {}
}

/// Answers the prompt as soon as it is pushed; `answer: nil` leaves it pending.
private final class AnsweringPusher: AIChatElicitationPushing {
    private let elicitations: AIChatElicitationCoordinator
    private let answer: MCPElicitationResult?
    private(set) var pushed: MCPElicitationCreateParams?

    init(elicitations: AIChatElicitationCoordinator, answer: MCPElicitationResult?) {
        self.elicitations = elicitations
        self.answer = answer
    }

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        pushed = params
        if let answer {
            elicitations.complete(id: params.id, result: answer)
        }
        return true
    }
}
