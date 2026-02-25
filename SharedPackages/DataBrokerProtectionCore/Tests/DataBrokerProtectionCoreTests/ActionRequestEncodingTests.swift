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

final class ActionRequestEncodingTests: XCTestCase {

    func testWhenStepContainsRawActionJSON_thenStepEncodingPreservesUnknownActionFields() throws {
        // Given: a step action payload that includes fields not declared by ClickAction.
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
                                "selector": "#submit"
                            }
                        ],
                        "someNewField": "hello-world"
                    }
                ]
            }
            """
        let step = try JSONDecoder().decode(Step.self, from: Data(stepJSON.utf8))

        // When: the step is re-encoded.
        let encodedStep = try JSONEncoder().encode(step)
        let stepObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: encodedStep) as? [String: Any])
        let actions = try XCTUnwrap(stepObject["actions"] as? [[String: Any]])
        let action = try XCTUnwrap(actions.first)

        // Then: broker-owned fields are preserved through Step-level encoding.
        XCTAssertEqual(action["actionType"] as? String, "click")
        XCTAssertEqual(action["id"] as? String, "click-1")
        XCTAssertEqual(action["someNewField"] as? String, "hello-world")
        let elements = try XCTUnwrap(action["elements"] as? [[String: Any]])
        XCTAssertEqual(elements.first?["selector"] as? String, "#submit")
    }

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
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil)))

        let encodedAction = try encodedActionPayload(from: params)

        XCTAssertEqual(encodedAction["actionType"] as? String, "navigate")
        XCTAssertEqual(encodedAction["id"] as? String, "navigate-1")
        XCTAssertEqual(encodedAction["url"] as? String, "https://example.com")
        XCTAssertEqual(encodedAction["someNewField"] as? String, "hello-world")
        XCTAssertEqual(encodedAction["someNewArrayField"] as? [String], ["one", "two"])
        XCTAssertEqual((encodedAction["anotherNewField"] as? [String: Any])?["flag"] as? Bool, true)
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
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil)))

        // When: encoding the action request payload for WebView injection.
        let encodedAction = try encodedActionPayload(from: params)

        // Then: nested condition payload is preserved.
        XCTAssertEqual(encodedAction["actionType"] as? String, "condition")
        XCTAssertEqual(encodedAction["id"] as? String, "condition-1")
        let expectations = try XCTUnwrap(encodedAction["expectations"] as? [[String: Any]])
        XCTAssertEqual(expectations.first?["selector"] as? String, ".results")
        let nestedActions = try XCTUnwrap(encodedAction["actions"] as? [[String: Any]])
        let nestedClick = try XCTUnwrap(nestedActions.first)
        XCTAssertEqual(nestedClick["actionType"] as? String, "click")
        XCTAssertEqual(nestedClick["id"] as? String, "click-1")
        XCTAssertEqual(nestedClick["someNewField"] as? String, "hello-world")
    }

    func testWhenActionDoesNotContainRawJSON_thenEncodingFallsBackToTypedAction() throws {
        let action = NavigateAction(id: "navigate-typed", actionType: .navigate, url: "https://example.com")
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil)))

        let encodedAction = try encodedActionPayload(from: params)

        XCTAssertEqual(encodedAction["actionType"] as? String, "navigate")
        XCTAssertEqual(encodedAction["id"] as? String, "navigate-typed")
        XCTAssertEqual(encodedAction["url"] as? String, "https://example.com")
        XCTAssertNil(encodedAction["someRandomField"])
    }

    func testWhenEmailConfirmationContinuationBuildsSyntheticNavigate_thenEncodingFallsBackToTypedAction() throws {
        let emailAction = EmailConfirmationAction(id: "email-1", actionType: .emailConfirmation, pollingTime: 1)
        let step = Step(type: .optOut, actions: [emailAction])
        let confirmationURL = URL(string: "https://example.com")!
        let actionsHandler = ActionsHandler.forEmailConfirmationContinuation(step, confirmationURL: confirmationURL)
        let continuationAction = try XCTUnwrap(actionsHandler.nextAction())
        let params = Params(state: ActionRequest(action: continuationAction, data: .userData(makeProfileQuery(), nil)))

        let encodedAction = try encodedActionPayload(from: params)

        XCTAssertEqual(encodedAction["actionType"] as? String, "navigate")
        XCTAssertEqual(encodedAction["id"] as? String, "email-1")
        XCTAssertEqual(encodedAction["url"] as? String, confirmationURL.absoluteString)
        XCTAssertNil(encodedAction["someRandomField"])
    }

    func testWhenActionContainsInvalidRawJSON_thenEncodingThrowsInvalidActionPayloadError() throws {
        // Given: an action with invalid raw payload shape (JSON array instead of JSON object).
        let action = NavigateAction(
            id: "navigate-invalid",
            actionType: .navigate,
            url: "https://example.com",
            json: Data("[]".utf8)
        )
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil)))

        // When / Then: encoding fails with a clear invalid action payload error.
        XCTAssertThrowsError(try JSONEncoder().encode(params)) { error in
            guard case EncodingError.invalidValue(_, let context) = error else {
                return XCTFail("Expected EncodingError.invalidValue, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Invalid action JSON payload")
        }
    }

    private func makeProfileQuery() -> ProfileQuery {
        ProfileQuery(firstName: "John",
                     lastName: "Doe",
                     city: "Miami",
                     state: "FL",
                     birthYear: 1985)
    }

    private func encodedActionPayload(from params: Params) throws -> [String: Any] {
        let encodedParams = try JSONEncoder().encode(params)
        let rootObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: encodedParams) as? [String: Any])
        let state = try XCTUnwrap(rootObject["state"] as? [String: Any])
        return try XCTUnwrap(state["action"] as? [String: Any])
    }
}
