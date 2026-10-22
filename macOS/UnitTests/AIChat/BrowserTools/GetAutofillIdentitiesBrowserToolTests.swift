//
//  GetAutofillIdentitiesBrowserToolTests.swift
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
import BrowserServicesKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class GetAutofillIdentitiesBrowserToolTests: XCTestCase {

    private var provider: StubIdentityProvider!
    private var tool: GetAutofillIdentitiesBrowserTool!
    private let context = BrowserToolCallContext(ownerTabID: "chat", ownerWindowToken: "window", isBurner: false, supportsElicitationForm: true)

    override func setUp() {
        super.setUp()
        provider = StubIdentityProvider()
        provider.saved = [Self.home, Self.work]
        tool = GetAutofillIdentitiesBrowserTool(identities: provider)
    }

    override func tearDown() {
        provider = nil
        tool = nil
        super.tearDown()
    }

    // MARK: - Prompt

    func testWhenAskedThenTheUserPicksFromTheSavedIdentities() async {
        let prompt = await tool.approvalPrompt(arguments: ["purpose": "to fill the checkout on Example Shoes"], context: context)

        XCTAssertEqual(prompt, .choose(message: "Share a saved identity with Duck.ai?", choices: ["1", "2"], meta: [
            "kind": "identityPicker",
            "purpose": "to fill the checkout on Example Shoes",
            "options": [
                ["value": "1", "title": "Home", "subtitle": "Jamie Rivera · Springfield"],
                ["value": "2", "title": "Sam Lee", "subtitle": "Sam Lee"]
            ]
        ]))
    }

    func testWhenNoPurposeIsGivenThenItIsLeftOutOfThePrompt() async throws {
        for arguments: JSONValue? in [nil, [:], ["purpose": "   "], ["purpose": .null]] {
            guard case .choose(_, _, let meta) = await tool.approvalPrompt(arguments: arguments, context: context) else {
                return XCTFail("expected a picker for \(String(describing: arguments))")
            }
            XCTAssertNil(meta?["purpose"])
        }
    }

    func testWhenThePurposeIsTooLongOrNotTextThenTheArgumentsAreInvalid() async {
        let tooLong = String(repeating: "a", count: GetAutofillIdentitiesBrowserTool.maxPurposeLength + 1)

        for arguments: JSONValue in [["purpose": .string(tooLong)], ["purpose": 5], "purpose"] {
            let prompt = await tool.approvalPrompt(arguments: arguments, context: context)
            XCTAssertEqual(prompt, .refuse(.invalidArguments), "\(arguments)")
        }
    }

    func testWhenNoIdentityIsSavedThenTheCallIsNotFoundWithoutAsking() async {
        provider.saved = []

        let prompt = await tool.approvalPrompt(arguments: nil, context: context)

        XCTAssertEqual(prompt, .refuse(.notFound))
    }

    // MARK: - Sharing

    /// Only the picked identity is shared, and only its non-empty fields.
    func testWhenTheUserPicksAnIdentityThenOnlyThatOneIsSharedWithoutEmptyFields() async {
        let result = await tool.execute(arguments: nil, context: context, approvedChoice: "1")

        XCTAssertEqual(result, .success([
            "identity": [
                "id": "1",
                "title": "Home",
                "name": ["first": "Jamie", "last": "Rivera"],
                "birthday": ["day": 14, "month": 6, "year": 1990],
                "address": ["street": "123 Example Street", "city": "Springfield", "province": "IL", "postalCode": "62701", "countryCode": "US"],
                "contact": ["mobilePhone": "555-0134", "email": "jamie@example.com"]
            ]
        ]))
    }

    func testWhenAnIdentityHasOnlyANameThenTheOtherGroupsAreLeftOut() async {
        let result = await tool.execute(arguments: nil, context: context, approvedChoice: "2")

        XCTAssertEqual(result, .success(["identity": ["id": "2", "name": ["first": "Sam", "last": "Lee"]]]))
    }

    func testWhenThePickedIdentityIsGoneThenItIsNotFound() async {
        let result = await tool.execute(arguments: nil, context: context, approvedChoice: "9")

        XCTAssertEqual(result, .failure(.notFound))
    }

    func testWhenRunWithoutThePicksApprovalThenNothingIsShared() async {
        let result = await tool.execute(arguments: nil, context: context)

        XCTAssertEqual(result, .failure(.denied))
    }

    // MARK: - Through the invoker

    func testWhenTheUserDeclinesOrPicksThenTheInvokerAnswersAccordingly() async {
        let elicitations = AIChatElicitationCoordinator(timeout: 5)
        let invoker = makeInvoker(elicitations: elicitations)

        let declined = await invoker.invoke(toolNamed: "getAutofillIdentities", arguments: nil, context: context,
                                            elicitationPusher: PickingPusher(elicitations: elicitations, answer: MCPElicitationResult(action: .decline)))
        let picked = await invoker.invoke(toolNamed: "getAutofillIdentities", arguments: nil, context: context,
                                          elicitationPusher: PickingPusher(elicitations: elicitations,
                                                                           answer: MCPElicitationResult(action: .accept, content: ["choice": "2"])))
        let notOffered = await invoker.invoke(toolNamed: "getAutofillIdentities", arguments: nil, context: context,
                                              elicitationPusher: PickingPusher(elicitations: elicitations,
                                                                               answer: MCPElicitationResult(action: .accept, content: ["choice": "7"])))

        XCTAssertEqual(declined, .failure(.denied))
        XCTAssertEqual(picked, .success(["identity": ["id": "2", "name": ["first": "Sam", "last": "Lee"]]]))
        XCTAssertEqual(notOffered, .failure(.invalidPermissionChoice))
    }

    func testWhenCalledInAFireWindowThenNothingIsAsked() async {
        let fire = BrowserToolCallContext(ownerTabID: "chat", ownerWindowToken: "window", isBurner: true, supportsElicitationForm: true)

        let prompt = await tool.approvalPrompt(arguments: nil, context: fire)
        let direct = await tool.execute(arguments: nil, context: fire, approvedChoice: "1")

        XCTAssertEqual(prompt, .refuse(.unavailable))
        XCTAssertEqual(direct, .failure(.unavailable))
    }

    func testWhenDescribedThenEveryCallIsApprovedByThePick() {
        XCTAssertEqual(tool.name, "getAutofillIdentities")
        XCTAssertEqual(tool.permissionMode, .ask)
        XCTAssertTrue(tool.approvesEachCall)
    }

    // MARK: -

    private func makeInvoker(elicitations: AIChatElicitationCoordinator) -> BrowserToolInvoker {
        let configuration = IdentityToolConfiguration()
        return BrowserToolInvoker(catalog: BrowserToolCatalog(tools: [tool], configuration: configuration),
                                  configuration: configuration,
                                  permissions: IdentityToolPermissions(),
                                  elicitations: elicitations,
                                  openedTabs: BrowserToolOpenedTabs())
    }

    private static let home = SecureVaultModels.Identity(id: 1, title: "Home", created: Date(), lastUpdated: Date(),
                                                         firstName: "Jamie", middleName: " ", lastName: "Rivera",
                                                         birthdayDay: 14, birthdayMonth: 6, birthdayYear: 1990,
                                                         addressStreet: "123 Example Street", addressStreet2: "", addressCity: "Springfield",
                                                         addressProvince: "IL", addressPostalCode: "62701", addressCountryCode: "us",
                                                         homePhone: nil, mobilePhone: "555-0134", emailAddress: "jamie@example.com")

    private static let work = SecureVaultModels.Identity(id: 2, title: "", created: Date(), lastUpdated: Date(), firstName: "Sam", lastName: "Lee")
}

@MainActor
private final class StubIdentityProvider: BrowserToolIdentityProviding {
    var saved: [SecureVaultModels.Identity] = []

    func identities() -> [SecureVaultModels.Identity] {
        saved
    }
}

private final class IdentityToolConfiguration: BrowserToolsConfiguration {
    let isEnabled = true
    func isToolEnabled(named name: String) -> Bool { true }
}

private final class IdentityToolPermissions: BrowserToolPermissionStoring {
    let storedDecisions: [String: BrowserToolPermissionState] = [:]
    func state(forToolNamed name: String) -> BrowserToolPermissionState { .ask }
    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String) {}
    func clearAll() {}
}

private final class PickingPusher: AIChatElicitationPushing {
    private let elicitations: AIChatElicitationCoordinator
    private let answer: MCPElicitationResult

    init(elicitations: AIChatElicitationCoordinator, answer: MCPElicitationResult) {
        self.elicitations = elicitations
        self.answer = answer
    }

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        elicitations.complete(id: params.id, result: answer)
        return true
    }
}
