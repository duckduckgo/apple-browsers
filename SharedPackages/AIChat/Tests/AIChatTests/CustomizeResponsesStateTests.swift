//
//  CustomizeResponsesStateTests.swift
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

import XCTest
@testable import AIChat

final class CustomizeResponsesStateTests: XCTestCase {

    private let clarifies = "Clarifies"

    // MARK: - Helpers

    // swiftlint:disable force_try
    private func jsonString(_ data: [String: Any]) -> String {
        let envelope: [String: Any] = ["version": "1", "data": data]
        let encoded = try! JSONSerialization.data(withJSONObject: envelope)
        return String(data: encoded, encoding: .utf8)!
    }
    // swiftlint:enable force_try

    private func object(_ data: [String: Any]) -> [String: Any] {
        ["version": "1", "data": data]
    }

    // MARK: - Empty / absent / malformed

    func testWhenCustomizationIsNilThenStateIsNone() {
        let state = CustomizeResponsesState.make(customizationValue: nil, activeValue: nil, clarifiesLabel: clarifies)
        XCTAssertEqual(state, .none)
    }

    func testWhenCustomizationIsEmptyStringThenNotCustomized() {
        let state = CustomizeResponsesState.make(customizationValue: "", activeValue: nil, clarifiesLabel: clarifies)
        XCTAssertFalse(state.hasCustomization)
        XCTAssertNil(state.subLabel)
    }

    func testWhenCustomizationIsMalformedJSONThenNotCustomized() {
        let state = CustomizeResponsesState.make(customizationValue: "{not valid json", activeValue: nil, clarifiesLabel: clarifies)
        XCTAssertFalse(state.hasCustomization)
        XCTAssertNil(state.subLabel)
    }

    func testWhenPayloadHasNoDataKeyThenNotCustomized() {
        let state = CustomizeResponsesState.make(customizationValue: #"{"version":"1"}"#, activeValue: nil, clarifiesLabel: clarifies)
        XCTAssertFalse(state.hasCustomization)
        XCTAssertNil(state.subLabel)
    }

    func testWhenAllFieldsDefaultOrEmptyThenNotCustomized() {
        let json = jsonString(["tone": "Default",
                               "length": "Default",
                               "assistantName": "",
                               "userName": "   ",
                               "shouldSeekClarity": false])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies)
        XCTAssertFalse(state.hasCustomization)
        XCTAssertNil(state.subLabel)
    }

    // MARK: - Payload accepted as String or already-decoded object

    func testParsesFromJSONString() {
        let state = CustomizeResponsesState.make(customizationValue: jsonString(["tone": "Formal"]),
                                                 activeValue: nil,
                                                 clarifiesLabel: clarifies)
        XCTAssertTrue(state.hasCustomization)
        XCTAssertEqual(state.subLabel, "Formal")
        XCTAssertFalse(state.isActive)
    }

    func testParsesFromDecodedObject() {
        let state = CustomizeResponsesState.make(customizationValue: object(["tone": "Formal"]),
                                                 activeValue: nil,
                                                 clarifiesLabel: clarifies)
        XCTAssertTrue(state.hasCustomization)
        XCTAssertEqual(state.subLabel, "Formal")
    }

    // MARK: - `active` interpretation

    func testActiveFromBoolTrue() {
        let state = CustomizeResponsesState.make(customizationValue: jsonString(["tone": "Formal"]), activeValue: true, clarifiesLabel: clarifies)
        XCTAssertTrue(state.isActive)
    }

    func testActiveFromBoolFalse() {
        let state = CustomizeResponsesState.make(customizationValue: jsonString(["tone": "Formal"]), activeValue: false, clarifiesLabel: clarifies)
        XCTAssertFalse(state.isActive)
    }

    func testActiveFromStringTrueIsCaseInsensitive() {
        let state = CustomizeResponsesState.make(customizationValue: nil, activeValue: "TRUE", clarifiesLabel: clarifies)
        XCTAssertTrue(state.isActive)
    }

    func testActiveFromStringFalse() {
        let state = CustomizeResponsesState.make(customizationValue: nil, activeValue: "false", clarifiesLabel: clarifies)
        XCTAssertFalse(state.isActive)
    }

    func testActiveFromUnknownTypeDefaultsToFalse() {
        let state = CustomizeResponsesState.make(customizationValue: nil, activeValue: 42, clarifiesLabel: clarifies)
        XCTAssertFalse(state.isActive)
    }

    // MARK: - Sub-label composition

    func testSubLabelOrdersToneLengthRolesThenClarifiesThenNames() {
        let json = jsonString(["tone": "T",
                               "length": "L",
                               "assistantRole": "AR",
                               "userRole": "UR",
                               "shouldSeekClarity": true,
                               "assistantName": "AN",
                               "userName": "UN"])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: "Clarifies", maxSubLabelLength: 100)
        XCTAssertTrue(state.hasCustomization)
        XCTAssertEqual(state.subLabel, "T, L, AR, UR, Clarifies, AN, UN")
    }

    func testDefaultValuedFieldsAreExcludedFromSubLabel() {
        let json = jsonString(["tone": "Default", "length": "Short"])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies, maxSubLabelLength: 100)
        XCTAssertEqual(state.subLabel, "Short")
    }

    func testClarifiesFragmentAppendedWhenShouldSeekClarity() {
        let json = jsonString(["shouldSeekClarity": true])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: "Clarifies", maxSubLabelLength: 100)
        XCTAssertTrue(state.hasCustomization)
        XCTAssertEqual(state.subLabel, "Clarifies")
    }

    func testAdditionalInstructionsCountAsCustomizedButAreNotShownInSubLabel() {
        let json = jsonString(["additionalInstructions": "Always be concise and cite sources"])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies)
        XCTAssertTrue(state.hasCustomization)
        XCTAssertNil(state.subLabel)
    }

    // MARK: - Truncation

    func testSubLabelExactlyAtMaxLengthIsNotTruncated() {
        let json = jsonString(["tone": "Friendly", "length": "Short"])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies, maxSubLabelLength: 15)
        XCTAssertEqual(state.subLabel, "Friendly, Short")
    }

    func testSubLabelTruncatesOnWordBoundaryWithEllipsis() {
        let json = jsonString(["tone": "Friendly", "length": "Detailed"])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies, maxSubLabelLength: 15)
        XCTAssertEqual(state.subLabel, "Friendly…")
    }

    func testSubLabelSingleWordLongerThanMaxIsHardTruncated() {
        let json = jsonString(["tone": "Supercalifragilistic"])
        let state = CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies, maxSubLabelLength: 15)
        XCTAssertEqual(state.subLabel, "Supercalifragil…")
    }

    func testSubLabelWithNonPositiveMaxLengthReturnsEmptyWithoutCrashing() {
        let json = jsonString(["tone": "Friendly", "length": "Detailed"])
        XCTAssertEqual(CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies, maxSubLabelLength: 0).subLabel, "")
        XCTAssertEqual(CustomizeResponsesState.make(customizationValue: json, activeValue: nil, clarifiesLabel: clarifies, maxSubLabelLength: -5).subLabel, "")
    }
}
