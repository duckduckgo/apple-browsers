//
//  MapperToModelTests.swift
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

import XCTest
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class MapperToModelTests: XCTestCase {

    private var sut = MapperToModel(mechanism: { _ in Data() })
    private var jsonDecoder: JSONDecoder!
    private var jsonEncoder: JSONEncoder!

    override func setUpWithError() throws {
        jsonDecoder = JSONDecoder()
        jsonEncoder = JSONEncoder()
    }

    func testMapToModel_validData() throws {
        // Given
        let brokerData = DataBroker(
            id: 1,
            name: "TestBroker",
            url: "https://example.com",
            steps: [],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(retryError: 1, confirmOptOutScan: 2, maintenanceScan: 3, maxAttempts: -1),
            parent: "ParentBroker",
            mirrorSites: [],
            optOutUrl: "https://example.com/opt-out",
            eTag: "",
            removedAt: nil
        )
        let jsonData = try jsonEncoder.encode(brokerData)
        let brokerDB = BrokerDB(id: 1, name: "TestBroker", json: jsonData, version: "1.0", url: "https://example.com", eTag: "", removedAt: nil)

        // When
        let result = try sut.mapToModel(brokerDB)

        // Then
        XCTAssertEqual(result.id, brokerDB.id)
        XCTAssertEqual(result.name, brokerDB.name)
        XCTAssertEqual(result.url, brokerData.url)
        XCTAssertEqual(result.version, brokerData.version)
        XCTAssertEqual(result.steps.count, brokerData.steps.count)
        XCTAssertEqual(result.parent, brokerData.parent)
        XCTAssertEqual(result.mirrorSites.count, brokerData.mirrorSites.count)
        XCTAssertEqual(result.optOutUrl, brokerData.optOutUrl)
    }

    func testMapToModel_missingOptionalFields() throws {
        // Given
        let brokerData = """
            {
                "name": "TestBroker",
                "url": "https://example.com",
                "steps": [],
                "version": "1.0",
                "schedulingConfig": {"retryError": 1, "confirmOptOutScan": 2, "maintenanceScan": 3, "maxAttempts": -1}
            }
            """.data(using: .utf8)!
        let brokerDB = BrokerDB(id: 1, name: "TestBroker", json: brokerData, version: "1.0", url: "https://example.com", eTag: "", removedAt: nil)

        // When
        let result = try sut.mapToModel(brokerDB)

        // Then
        XCTAssertNil(result.parent)
        XCTAssertEqual(result.mirrorSites.count, 0)
        XCTAssertEqual(result.optOutUrl, "")
    }

    func testMapToModel_invalidJSONStructure() throws {
        // Given
        let invalidJsonData = """
            {
                "invalidKey": "value"
            }
            """.data(using: .utf8)!
        let brokerDB = BrokerDB(id: 1,
                                name: "InvalidBroker",
                                json: invalidJsonData,
                                version: "1.0",
                                url: "https://example.com",
                                eTag: "",
                                removedAt: nil)

        // When & Then
        XCTAssertThrowsError(try sut.mapToModel(brokerDB)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testMapToModel_missingUrlFallbackToName() throws {
        // Given
        let brokerData = """
            {
                "name": "TestBroker",
                "steps": [],
                "version": "1.0",
                "schedulingConfig": {"retryError": 1, "confirmOptOutScan": 2, "maintenanceScan": 3, "maxAttempts": -1}
            }
            """.data(using: .utf8)!
        let brokerDB = BrokerDB(id: 1, name: "TestBroker", json: brokerData, version: "1.0", url: "", eTag: "", removedAt: nil)

        // When
        let result = try sut.mapToModel(brokerDB)

        // Then
        XCTAssertEqual(result.url, brokerDB.name)
    }

    func testMapToModel_legacyNormalizedBrokerJSON_decodesSuccessfully() throws {
        // Given
        let legacyBrokerJSON = """
            {
                "name": "ExampleBroker",
                "url": "example.com",
                "steps": [
                    {
                        "stepType": "scan",
                        "actions": [
                            {
                                "actionType": "click",
                                "id": "click-1",
                                "selector": "#submit",
                                "dataSource": "userProfile",
                                "elements": [
                                    {
                                        "type": "button",
                                        "selector": "#submit",
                                        "parent": {
                                            "selector": ".button-parent"
                                        },
                                        "multiple": true,
                                        "min": "1",
                                        "max": "3",
                                        "failSilently": true
                                    }
                                ]
                            },
                            {
                                "actionType": "fillForm",
                                "id": "fill-1",
                                "selector": "#opt-out-form",
                                "dataSource": "userProfile",
                                "elements": [
                                    {
                                        "type": "email",
                                        "selector": "input[type='email']",
                                        "parent": {
                                            "selector": "#email-wrapper"
                                        },
                                        "multiple": false,
                                        "min": "1",
                                        "max": "1",
                                        "failSilently": false
                                    }
                                ]
                            }
                        ]
                    }
                ],
                "version": "1.0.0",
                "schedulingConfig": {"retryError": 48, "confirmOptOutScan": 72, "maintenanceScan": 120, "maxAttempts": -1},
                "optOutUrl": "https://example.com"
            }
            """.data(using: .utf8)!
        let brokerDB = BrokerDB(
            id: 1,
            name: "ExampleBroker",
            json: legacyBrokerJSON,
            version: "1.0.0",
            url: "example.com",
            eTag: "legacy-etag",
            removedAt: nil
        )

        // When
        let result = try sut.mapToModel(brokerDB)

        // Then
        XCTAssertEqual(result.name, "ExampleBroker")
        XCTAssertEqual(result.url, "example.com")
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps.first?.actions.count, 2)
        XCTAssertEqual(result.steps.first?.actions.first?.actionType, .click)
        XCTAssertEqual(result.steps.first?.actions.last?.actionType, .fillForm)

        let fillFormAction = try XCTUnwrap(result.steps.first?.actions.last as? FillFormAction)
        XCTAssertEqual(fillFormAction.elements.first?.type, "email")
        XCTAssertTrue(fillFormAction.needsEmail)
    }

    func testMapToModel_rawBrokerDBJSON_preservesUnknownActionFieldsWhenEncodingActionRequest() throws {
        // Given: DB broker JSON includes action fields that native models do not define.
        let rawBrokerJSON = """
            {
                "name": "ExampleBroker",
                "url": "example.com",
                "steps": [
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
                ],
                "version": "1.0.0",
                "schedulingConfig": {"retryError": 48, "confirmOptOutScan": 72, "maintenanceScan": 120, "maxAttempts": -1},
                "optOutUrl": "https://example.com"
            }
            """.data(using: .utf8)!
        let brokerDB = BrokerDB(
            id: 1,
            name: "ExampleBroker",
            json: rawBrokerJSON,
            version: "1.0.0",
            url: "example.com",
            eTag: "etag-raw",
            removedAt: nil
        )

        // When: broker JSON is decoded to typed model and action request payload is encoded for WebView injection.
        let mappedBroker = try sut.mapToModel(brokerDB)
        let action = try XCTUnwrap(mappedBroker.steps.first?.actions.first)
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil)))
        let rawActionPayload = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])

        // Then: DB -> model mapping still preserves new fields for final action payload encoding.
        XCTAssertEqual(rawActionPayload["actionType"] as? String, "navigate")
        XCTAssertEqual(rawActionPayload["someNewField"] as? String, "hello-world")
        XCTAssertEqual((rawActionPayload["anotherNewField"] as? [String: Any])?["flag"] as? Bool, true)
    }

    func testMapToModel_legacyBrokerDBJSON_canStillEncodeActionRequestPayload() throws {
        // Given: legacy normalized DB JSON with fields trimmed from current native action structs.
        let legacyBrokerJSON = """
            {
                "name": "ExampleBroker",
                "url": "example.com",
                "steps": [
                    {
                        "stepType": "scan",
                        "actions": [
                            {
                                "actionType": "fillForm",
                                "id": "fill-1",
                                "selector": "#opt-out-form",
                                "dataSource": "userProfile",
                                "elements": [
                                    {
                                        "type": "email",
                                        "selector": "input[type='email']",
                                        "parent": {
                                            "selector": "#email-wrapper"
                                        },
                                        "multiple": false,
                                        "min": "1",
                                        "max": "1",
                                        "failSilently": false
                                    }
                                ]
                            }
                        ]
                    }
                ],
                "version": "1.0.0",
                "schedulingConfig": {"retryError": 48, "confirmOptOutScan": 72, "maintenanceScan": 120, "maxAttempts": -1},
                "optOutUrl": "https://example.com"
            }
            """.data(using: .utf8)!
        let brokerDB = BrokerDB(
            id: 1,
            name: "ExampleBroker",
            json: legacyBrokerJSON,
            version: "1.0.0",
            url: "example.com",
            eTag: "legacy-etag",
            removedAt: nil
        )

        // When: broker JSON is mapped and then encoded as a WebView action payload.
        let mappedBroker = try sut.mapToModel(brokerDB)
        let action = try XCTUnwrap(mappedBroker.steps.first?.actions.first)
        let params = Params(state: ActionRequest(action: action, data: .userData(makeProfileQuery(), nil)))
        let rawActionPayload = try XCTUnwrap((try params.toDictionary()["state"] as? [String: Any])?["action"] as? [String: Any])

        // Then: legacy fields are still forwarded because encoding uses attached action JSON.
        XCTAssertEqual(rawActionPayload["actionType"] as? String, "fillForm")
        XCTAssertEqual(rawActionPayload["id"] as? String, "fill-1")
        XCTAssertEqual(rawActionPayload["selector"] as? String, "#opt-out-form")
        XCTAssertEqual(rawActionPayload["dataSource"] as? String, "userProfile")

        let elements = try XCTUnwrap(rawActionPayload["elements"] as? [[String: Any]])
        let firstElement = try XCTUnwrap(elements.first)
        XCTAssertEqual(firstElement["type"] as? String, "email")
        XCTAssertEqual(firstElement["selector"] as? String, "input[type='email']")
        XCTAssertEqual((firstElement["parent"] as? [String: Any])?["selector"] as? String, "#email-wrapper")
    }

    // MARK: - Helpers

    private func makeProfileQuery() -> ProfileQuery {
        ProfileQuery(firstName: "John", lastName: "Doe", city: "Miami", state: "FL", birthYear: 1985)
    }
}
