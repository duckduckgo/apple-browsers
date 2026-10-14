//
//  RawJSONSettingsLocatorTests.swift
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
@testable import PrivacyConfig

final class RawJSONSettingsLocatorTests: XCTestCase {

    /// The located `settings` text of each feature, and of each sub-feature as `feature.subfeature`.
    private func locatedSettings(in config: String) -> [String: String]? {
        let locator = RawJSONSettingsLocator(data: Data(config.utf8))
        guard let located = locator.locate() else { return nil }

        func text(_ range: Range<Int>) -> String {
            String(decoding: locator.bytes[range], as: UTF8.self)
        }

        var result = [String: String]()
        for (name, ranges) in located {
            if let settings = ranges.settings {
                result[name] = text(settings)
            }
            for (subfeatureName, settings) in ranges.subfeatureSettings {
                result["\(name).\(subfeatureName)"] = text(settings)
            }
        }
        return result
    }

    func testWhenSettingsAreNestedThenTheirTextIsLocatedAsWritten() {
        let config = #"{"version": 1, "features": {"a": {"state": "enabled", "settings": {"zulu": {"yankee": 1, "alpha": [2, {"x": null}]}, "bravo": true}}}}"#

        XCTAssertEqual(locatedSettings(in: config), ["a": #"{"zulu": {"yankee": 1, "alpha": [2, {"x": null}]}, "bravo": true}"#])
    }

    func testWhenStringsHoldQuotesBracesAndBackslashesThenTheyDoNotEndTheValue() {
        let config = #"{"features": {"a": {"settings": {"s": "quote \" brace } bracket ] backslash \\", "t": "\\\"}"}, "state": "enabled"}}}"#

        XCTAssertEqual(locatedSettings(in: config), ["a": #"{"s": "quote \" brace } bracket ] backslash \\", "t": "\\\"}"}"#])
    }

    func testWhenSubfeaturesHaveSettingsThenEachIsLocated() {
        let config = #"{"features": {"a": {"state": "enabled", "features": {"one": {"state": "enabled", "settings": {"zulu": 1, "alpha": 2}}, "two": {"state": "enabled"}}}}}"#

        XCTAssertEqual(locatedSettings(in: config), ["a.one": #"{"zulu": 1, "alpha": 2}"#])
    }

    func testWhenJSONHasWhitespaceAndNewlinesThenSettingsAreLocated() {
        let config = "{\n\t\"features\" :\r\n {\n  \"a\" : { \"settings\" :\n {\"zulu\": 1 ,\n \"alpha\": 2} }\n }\n}\n"

        XCTAssertEqual(locatedSettings(in: config), ["a": "{\"zulu\": 1 ,\n \"alpha\": 2}"])
    }

    func testWhenKeysHoldEscapesThenTheyAreDecoded() {
        let config = #"{"features": {"café": {"settings": {"zulu": 1}}}}"#

        XCTAssertEqual(locatedSettings(in: config), ["café": #"{"zulu": 1}"#])
    }

    func testWhenSettingsHaveIntegerLikeKeysThenTheirTextIsLocatedAsWritten() {
        let config = #"{"features": {"a": {"settings": {"loading": 1, "0": 2, "zulu": 3}}}}"#

        XCTAssertEqual(locatedSettings(in: config), ["a": #"{"loading": 1, "0": 2, "zulu": 3}"#])
    }

    func testWhenAKeyIsRepeatedThenItsLastValueIsLocated() {
        let config = #"{"features": {"a": {"settings": {"first": 1}, "settings": {"second": 2}}}}"#

        XCTAssertEqual(locatedSettings(in: config), ["a": #"{"second": 2}"#])
    }

    func testWhenSettingsAreEmptyOrMissingThenOnlyPresentOnesAreLocated() {
        let config = #"{"features": {"a": {"settings": {}}, "b": {"state": "enabled"}, "c": []}}"#

        XCTAssertEqual(locatedSettings(in: config), ["a": "{}"])
    }

    func testWhenFeaturesIsNotAnObjectThenNothingIsLocated() {
        XCTAssertNil(locatedSettings(in: #"{"features": []}"#))
        XCTAssertNil(locatedSettings(in: #"{"version": 1}"#))
        XCTAssertNil(locatedSettings(in: "[]"))
    }

    func testWhenJSONIsTruncatedThenNothingIsLocated() {
        XCTAssertNil(locatedSettings(in: #"{"features": {"a": {"settings": {"zulu": 1"#))
        XCTAssertNil(locatedSettings(in: #"{"features": {"a": {"settings": "unterminated"#))
    }
}
