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

    func testWhenActionContainsRawJSON_thenEncodingUsesRawActionPayload() throws {
        let stepJSON = """
            {
                "stepType": "scan",
                "actions": [
                    {
                        "actionType": "navigate",
                        "id": "navigate-1",
                        "url": "https://example.com",
                        "brokerOwnedField": "preserve-me",
                        "brokerOwnedArray": ["one", "two"],
                        "brokerOwnedNested": {
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
        XCTAssertEqual(encodedAction["brokerOwnedField"] as? String, "preserve-me")
        XCTAssertEqual(encodedAction["brokerOwnedArray"] as? [String], ["one", "two"])
        XCTAssertEqual((encodedAction["brokerOwnedNested"] as? [String: Any])?["flag"] as? Bool, true)
    }

    func testWhenActionDoesNotContainRawJSON_thenEncodingFallsBackToTypedAction() throws {
        let action = NavigateAction(id: "navigate-typed", actionType: .navigate, url: "https://example.com")
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil)))

        let encodedAction = try encodedActionPayload(from: params)

        XCTAssertEqual(encodedAction["actionType"] as? String, "navigate")
        XCTAssertEqual(encodedAction["id"] as? String, "navigate-typed")
        XCTAssertEqual(encodedAction["url"] as? String, "https://example.com")
        XCTAssertNil(encodedAction["brokerOwnedField"])
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
        XCTAssertNil(encodedAction["brokerOwnedField"])
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
