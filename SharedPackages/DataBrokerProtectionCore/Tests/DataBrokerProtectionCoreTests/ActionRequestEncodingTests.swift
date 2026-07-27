//
//  ActionRequestEncodingTests.swift
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

import XCTest
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class ActionRequestEncodingTests: XCTestCase {

    func testWhenActionContainsRawJSON_thenEncodingUsesRawActionPayload() throws {
        let stepJSON = """
            {
                "stepType": "scan",
                "actions": [
                    {
                        "actionType": "navigate",
                        "id": "navigate-1",
                        "url": "https://example.com",
                        "someNewField": "hello-world",
                        "someNewArrayField": ["one", "two"],
                        "anotherNewField": {
                            "flag": true
                        }
                    }
                ]
            }
            """
        let step = try JSONDecoder().decode(Step.self, from: Data(stepJSON.utf8))
        let action = try XCTUnwrap(step.actions.first)

        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, [:])))
        let rawActionPayload = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])

        XCTAssertEqual(rawActionPayload["actionType"] as? String, "navigate")
        XCTAssertEqual(rawActionPayload["id"] as? String, "navigate-1")
        XCTAssertEqual(rawActionPayload["url"] as? String, "https://example.com")
        XCTAssertEqual(rawActionPayload["someNewField"] as? String, "hello-world")
        XCTAssertEqual(rawActionPayload["someNewArrayField"] as? [String], ["one", "two"])
        XCTAssertEqual((rawActionPayload["anotherNewField"] as? [String: Any])?["flag"] as? Bool, true)
    }

    func testWhenConditionActionContainsNestedActions_thenActionRequestEncodingPreservesNestedConditionPayload() throws {
        // Given: a condition action with nested actions and expectations not modeled by ConditionAction.
        let stepJSON = """
            {
                "stepType": "scan",
                "actions": [
                    {
                        "actionType": "condition",
                        "id": "condition-1",
                        "expectations": [
                            {
                                "type": "element",
                                "selector": ".results"
                            }
                        ],
                        "actions": [
                            {
                                "actionType": "click",
                                "id": "click-1",
                                "elements": [
                                    {
                                        "type": "button",
                                        "selector": ".load-more"
                                    }
                                ],
                                "someNewField": "hello-world"
                            }
                        ]
                    }
                ]
            }
            """
        let step = try JSONDecoder().decode(Step.self, from: Data(stepJSON.utf8))
        let action = try XCTUnwrap(step.actions.first)

        // When: encoding the action request payload for WebView injection.
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, [:])))
        let rawActionPayload = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])

        // Then: nested condition payload is preserved.
        XCTAssertEqual(rawActionPayload["actionType"] as? String, "condition")
        XCTAssertEqual(rawActionPayload["id"] as? String, "condition-1")
        let expectations = try XCTUnwrap(rawActionPayload["expectations"] as? [[String: Any]])
        XCTAssertEqual(expectations.first?["selector"] as? String, ".results")
        let nestedActions = try XCTUnwrap(rawActionPayload["actions"] as? [[String: Any]])
        let nestedClick = try XCTUnwrap(nestedActions.first)
        XCTAssertEqual(nestedClick["actionType"] as? String, "click")
        XCTAssertEqual(nestedClick["id"] as? String, "click-1")
        XCTAssertEqual(nestedClick["someNewField"] as? String, "hello-world")
    }

    func testWhenActionDoesNotContainRawJSON_thenEncodingFallsBackToTypedAction() throws {
        let action = NavigateAction(id: "navigate-typed", actionType: .navigate, url: "https://example.com")

        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, [:])))
        let rawActionPayload = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])

        XCTAssertEqual(rawActionPayload["actionType"] as? String, "navigate")
        XCTAssertEqual(rawActionPayload["id"] as? String, "navigate-typed")
        XCTAssertEqual(rawActionPayload["url"] as? String, "https://example.com")
        XCTAssertNil(rawActionPayload["someRandomField"])
    }

    func testWhenEmailConfirmationContinuationBuildsSyntheticNavigate_thenEncodingFallsBackToTypedAction() throws {
        let emailAction = EmailConfirmationAction(id: "email-1", actionType: .emailConfirmation, pollingTime: 1)
        let step = Step(type: .optOut, actions: [emailAction])
        let confirmationURL = URL(string: "https://example.com")!
        let actionsHandler = ActionsHandler.forEmailConfirmationContinuation(step, confirmationURL: confirmationURL)
        let continuationAction = try XCTUnwrap(actionsHandler.nextAction())

        let params = Params(state: ActionRequest(action: continuationAction, data: .userData(makeProfileQuery(), nil, nil, [:])))
        let rawActionPayload = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])

        XCTAssertEqual(rawActionPayload["actionType"] as? String, "navigate")
        XCTAssertEqual(rawActionPayload["id"] as? String, "email-1")
        XCTAssertEqual(rawActionPayload["url"] as? String, confirmationURL.absoluteString)
        XCTAssertNil(rawActionPayload["someRandomField"])
    }

    func testWhenActionContainsInvalidRawJSON_thenEncodingThrowsInvalidActionPayloadError() throws {
        // Given: an action with invalid raw payload shape (JSON array instead of JSON object).
        let action = NavigateAction(
            id: "navigate-invalid",
            actionType: .navigate,
            url: "https://example.com",
            json: Data("[]".utf8)
        )
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, [:])))

        // When / Then: encoding fails with a clear invalid action payload error.
        XCTAssertThrowsError(try JSONEncoder().encode(params)) { error in
            guard case EncodingError.invalidValue(_, let context) = error else {
                return XCTFail("Expected EncodingError.invalidValue, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Invalid action JSON payload")
        }
    }

    func testWhenEmailDataIsEmpty_thenEmailDataKeyIsOmittedFromPayload() throws {
        let action = NavigateAction(id: "navigate-1", actionType: .navigate, url: "https://example.com")
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, [:])))

        let state = try XCTUnwrap(try params.toDictionary()["state"] as? [String: Any])
        let data = try XCTUnwrap(state["data"] as? [String: Any])

        // Omit emailData entirely when the bag is empty — keeps the payload shape identical to
        // pre-getEmailData jobs for the overwhelming majority of actions that don't need it.
        XCTAssertNil(data["emailData"])
    }

    func testWhenEmailDataIsPopulated_thenEmailDataAppearsInPayload() throws {
        let action = FillFormAction(id: "fill-1", actionType: .fillForm, elements: [.init(type: "verificationCode")])
        let emailData = ["verificationCode": "123456", "token": "abc-def"]
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, emailData)))

        let state = try XCTUnwrap(try params.toDictionary()["state"] as? [String: Any])
        let data = try XCTUnwrap(state["data"] as? [String: Any])
        let emittedEmailData = try XCTUnwrap(data["emailData"] as? [String: String])

        XCTAssertEqual(emittedEmailData, emailData)
    }

    func testWhenGenerateEmailAndGetEmailDataPopulateRunner_thenWirePayloadHasFetchedEmailAndEmailDataAndNoEmailMirror() throws {
        let action = FillFormAction(id: "fill-vcode", actionType: .fillForm, elements: [.init(type: "verificationCode")])
        let extractedProfile = ExtractedProfile(id: 42, name: "John Doe")
        let fetchedEmail = FetchedEmail(email: "disposable@duck.com")
        let emailData: ExtractedEmailData = ["verificationCode": "123456"]
        let params = Params(state: ActionRequest(action: action,
                                                  data: .userData(makeProfileQuery(),
                                                                  extractedProfile,
                                                                  fetchedEmail,
                                                                  emailData)))

        let state = try XCTUnwrap(try params.toDictionary()["state"] as? [String: Any])
        let data = try XCTUnwrap(state["data"] as? [String: Any])

        XCTAssertEqual((data["fetchedEmail"] as? [String: String])?["email"], "disposable@duck.com")
        XCTAssertEqual(data["emailData"] as? [String: String], ["verificationCode": "123456"])
        let encodedProfile = try XCTUnwrap(data["extractedProfile"] as? [String: Any])
        XCTAssertNil(encodedProfile["email"])
    }

    func testWhenLegacyBrokerFillForm_thenWirePayloadCarriesExtractedProfileEmail() throws {
        let action = FillFormAction(id: "fill-email", actionType: .fillForm, elements: [.init(type: "email")])
        let extractedProfile = ExtractedProfile(id: 42, name: "John Doe", email: "legacy-disposable@duck.com")
        let params = Params(state: ActionRequest(action: action,
                                                  data: .userData(makeProfileQuery(),
                                                                  extractedProfile,
                                                                  nil,
                                                                  [:])))

        let state = try XCTUnwrap(try params.toDictionary()["state"] as? [String: Any])
        let data = try XCTUnwrap(state["data"] as? [String: Any])

        let encodedProfile = try XCTUnwrap(data["extractedProfile"] as? [String: Any])
        XCTAssertEqual(encodedProfile["email"] as? String, "legacy-disposable@duck.com")
        XCTAssertNil(data["fetchedEmail"])
        XCTAssertNil(data["emailData"])
    }

    func testWhenActionElementsContainBooleans_thenTheyEncodeAsJSONBooleansNotNumbers() throws {
        // Regression: booleans decoded from JSON bridge to NSNumber. When the custom encoder
        // (CodableExtension) matched `Int` before `Bool`, `NSNumber(true) as? Int` succeeded and
        // `true`/`false` were re-encoded as `1`/`0`. That broke content-scope-scripts' strict
        // `element.multiple === true` check, so only the first element was ever clicked.
        // This exercises the nested-in-array encoder path (elements[]).
        let stepJSON = """
            {
                "stepType": "scan",
                "actions": [
                    {
                        "actionType": "click",
                        "id": "click-1",
                        "elements": [
                            {
                                "type": "button",
                                "selector": ".see-more",
                                "multiple": true,
                                "failSilently": false,
                                "passthroughCount": 3
                            }
                        ]
                    }
                ]
            }
            """
        let step = try JSONDecoder().decode(Step.self, from: Data(stepJSON.utf8))
        let action = try XCTUnwrap(step.actions.first)

        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, [:])))
        let rawAction = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])
        let element = try XCTUnwrap((rawAction["elements"] as? [[String: Any]])?.first)

        // Booleans must stay JSON booleans, both true and false.
        XCTAssertTrue(isJSONBoolean(element["multiple"]), "`multiple` must encode as a JSON boolean, not a number")
        XCTAssertEqual(element["multiple"] as? Bool, true)
        XCTAssertTrue(isJSONBoolean(element["failSilently"]), "`failSilently` must encode as a JSON boolean, not a number")
        XCTAssertEqual(element["failSilently"] as? Bool, false)

        // And genuine integers must NOT be misclassified as booleans by the fix.
        XCTAssertFalse(isJSONBoolean(element["passthroughCount"]), "integers must not be coerced to booleans")
        XCTAssertEqual(element["passthroughCount"] as? Int, 3)

        // Sanity: string fields still pass through.
        XCTAssertEqual(element["selector"] as? String, ".see-more")
    }

    func testWhenActionContainsTopLevelBoolean_thenItEncodesAsJSONBooleanNotNumber() throws {
        // Same corruption, but via the top-level object encoder path (keyed container).
        let stepJSON = """
            {
                "stepType": "scan",
                "actions": [
                    {
                        "actionType": "click",
                        "id": "click-1",
                        "elements": [ { "type": "button", "selector": ".x" } ],
                        "topLevelFlag": true
                    }
                ]
            }
            """
        let step = try JSONDecoder().decode(Step.self, from: Data(stepJSON.utf8))
        let action = try XCTUnwrap(step.actions.first)

        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil, nil, [:])))
        let rawAction = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])

        XCTAssertTrue(isJSONBoolean(rawAction["topLevelFlag"]), "top-level booleans must encode as JSON booleans, not numbers")
        XCTAssertEqual(rawAction["topLevelFlag"] as? Bool, true)
    }

    /// True only for genuine JSON booleans. `JSONSerialization` decodes JSON `true`/`false` into a
    /// `CFBoolean`-backed `NSNumber`, whereas JSON numbers decode into a `CFNumber`-backed one. A plain
    /// `as? Bool` cannot distinguish them (`NSNumber(1) as? Bool == true`), so we check the CoreFoundation
    /// type id directly — the only reliable way to assert "this stayed a boolean, not a 1".
    private func isJSONBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func makeProfileQuery() -> ProfileQuery {
        ProfileQuery(firstName: "John", lastName: "Doe", city: "Miami", state: "FL", birthYear: 1985)
    }
}
