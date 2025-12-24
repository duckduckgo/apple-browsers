//
//  DetectorDataTests.swift
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
@testable import PrivacyDashboard

final class DetectorDataTests: XCTestCase {

    // MARK: - Initialization

    func testWhenInitializedWithDictionaryThenRawDataIsStored() {
        let inputDict: [String: Any] = [
            "detector1": ["detected": true, "results": "test"]
        ]
        let detectorData = DetectorData(from: inputDict)

        XCTAssertEqual(detectorData.rawData.count, 1)
        XCTAssertNotNil(detectorData.rawData["detector1"])
    }

    func testWhenInitializedWithEmptyDictionaryThenRawDataIsEmpty() {
        let inputDict: [String: Any] = [:]
        let detectorData = DetectorData(from: inputDict)

        XCTAssertTrue(detectorData.rawData.isEmpty)
    }

    // MARK: - Flattened Metrics - Default Properties

    func testWhenFlattenedMetricsWithDefaultPropertiesThenIncludesDetectedAndResults() {
        let inputDict: [String: Any] = [
            "detector1": [
                "detected": true,
                "results": "test-result",
                "ignored": "should-be-ignored"
            ]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.detected"], "true")
        XCTAssertEqual(flattened["detector1.results"], "test-result")
        XCTAssertNil(flattened["detector1.ignored"])
    }

    func testWhenFlattenedMetricsWithMultipleDetectorsThenAllDetectorsAreIncluded() {
        let inputDict: [String: Any] = [
            "detector1": ["detected": true, "results": "result1"],
            "detector2": ["detected": false, "results": "result2"]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.detected"], "true")
        XCTAssertEqual(flattened["detector1.results"], "result1")
        XCTAssertEqual(flattened["detector2.detected"], "false")
        XCTAssertEqual(flattened["detector2.results"], "result2")
        XCTAssertEqual(flattened.count, 4)
    }

    // MARK: - Flattened Metrics - Custom Properties

    func testWhenFlattenedMetricsWithCustomPropertiesThenOnlyIncludedPropertiesAreReturned() {
        let inputDict: [String: Any] = [
            "detector1": [
                "detected": true,
                "results": "test-result",
                "customProp": "custom-value",
                "ignored": "should-be-ignored"
            ]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics(includedProperties: ["detected", "customProp"])

        XCTAssertEqual(flattened["detector1.detected"], "true")
        XCTAssertEqual(flattened["detector1.customProp"], "custom-value")
        XCTAssertNil(flattened["detector1.results"])
        XCTAssertNil(flattened["detector1.ignored"])
        XCTAssertEqual(flattened.count, 2)
    }

    func testWhenFlattenedMetricsWithEmptyIncludedPropertiesThenReturnsEmptyDictionary() {
        let inputDict: [String: Any] = [
            "detector1": ["detected": true, "results": "test"]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics(includedProperties: [])

        XCTAssertTrue(flattened.isEmpty)
    }

    // MARK: - Flattened Metrics - Non-Dictionary Values

    func testWhenDetectorValueIsNotDictionaryThenItIsSkipped() {
        let inputDict: [String: Any] = [
            "detector1": ["detected": true],
            "detector2": "not-a-dictionary",
            "detector3": ["detected": false]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.detected"], "true")
        XCTAssertEqual(flattened["detector3.detected"], "false")
        XCTAssertNil(flattened["detector2.detected"])
        XCTAssertEqual(flattened.count, 2)
    }

    // MARK: - String Value Conversion - Bool

    func testWhenValueIsBoolThenConvertsToString() {
        let inputDict: [String: Any] = [
            "detector1": ["detected": true],
            "detector2": ["detected": false]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.detected"], "true")
        XCTAssertEqual(flattened["detector2.detected"], "false")
    }

    // MARK: - String Value Conversion - String

    func testWhenValueIsStringThenReturnsAsIs() {
        let inputDict: [String: Any] = [
            "detector1": ["results": "test-string"]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.results"], "test-string")
    }

    // MARK: - String Value Conversion - Number

    func testWhenValueIsNumberThenConvertsToString() {
        let inputDict: [String: Any] = [
            "detector1": ["count": 42],
            "detector2": ["count": 3.14]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics(includedProperties: ["count"])

        XCTAssertEqual(flattened["detector1.count"], "42")
        XCTAssertEqual(flattened["detector2.count"], "3.14")
    }

    // MARK: - String Value Conversion - Array

    func testWhenValueIsEmptyArrayThenReturnsEmptyString() {
        let inputDict: [String: Any] = [
            "detector1": ["results": []]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.results"], "")
    }

    func testWhenValueIsArrayOfStringsThenJoinsWithComma() {
        let inputDict: [String: Any] = [
            "detector1": ["results": ["item1", "item2", "item3"]]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.results"], "item1,item2,item3")
    }

    func testWhenValueIsArrayOfMixedTypesThenConvertsAndJoins() {
        let inputDict: [String: Any] = [
            "detector1": ["results": [true, "string", 42]]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.results"], "true,string,42")
    }

    func testWhenValueIsNestedArrayThenRecursivelyConverts() {
        let inputDict: [String: Any] = [
            "detector1": ["results": [["nested", "array"], "string"]]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertNotNil(flattened["detector1.results"])
        XCTAssertTrue(flattened["detector1.results"]!.contains("nested"))
        XCTAssertTrue(flattened["detector1.results"]!.contains("array"))
    }

    // MARK: - String Value Conversion - Dictionary

    func testWhenValueIsDictionaryThenConvertsToJSONString() {
        let inputDict: [String: Any] = [
            "detector1": [
                "results": [
                    "key1": "value1",
                    "key2": 42
                ]
            ]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        let jsonString = flattened["detector1.results"]
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("key1"))
        XCTAssertTrue(jsonString!.contains("value1"))
        XCTAssertTrue(jsonString!.contains("key2"))
        XCTAssertTrue(jsonString!.contains("42"))
    }

    // MARK: - String Value Conversion - Other Types

    func testWhenValueIsUnsupportedTypeThenConvertsToStringDescription() {
        let inputDict: [String: Any] = [
            "detector1": ["results": Date()]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        let result = flattened["detector1.results"]
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isEmpty)
    }

    // MARK: - Complex Scenarios

    func testWhenFlattenedMetricsWithComplexNestedStructureThenHandlesCorrectly() {
        let inputDict: [String: Any] = [
            "detector1": [
                "detected": true,
                "results": ["item1", "item2"],
                "metadata": ["key": "value"]
            ],
            "detector2": [
                "detected": false,
                "results": "simple-string",
                "count": 100
            ]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["detector1.detected"], "true")
        XCTAssertEqual(flattened["detector1.results"], "item1,item2")
        XCTAssertNil(flattened["detector1.metadata"])
        XCTAssertEqual(flattened["detector2.detected"], "false")
        XCTAssertEqual(flattened["detector2.results"], "simple-string")
        XCTAssertNil(flattened["detector2.count"])
    }

    func testWhenFlattenedMetricsWithMultipleDetectorsAndCustomPropertiesThenFiltersCorrectly() {
        let inputDict: [String: Any] = [
            "detector1": [
                "detected": true,
                "results": "result1",
                "custom": "custom1"
            ],
            "detector2": [
                "detected": false,
                "results": "result2",
                "custom": "custom2"
            ]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics(includedProperties: ["detected", "custom"])

        XCTAssertEqual(flattened["detector1.detected"], "true")
        XCTAssertEqual(flattened["detector1.custom"], "custom1")
        XCTAssertEqual(flattened["detector2.detected"], "false")
        XCTAssertEqual(flattened["detector2.custom"], "custom2")
        XCTAssertNil(flattened["detector1.results"])
        XCTAssertNil(flattened["detector2.results"])
        XCTAssertEqual(flattened.count, 4)
    }

    // MARK: - Real-World Data Structure

    func testWhenInitializedWithRealWorldDetectorDataThenFlattensCorrectly() {
        let inputDict: [String: Any] = [
            "botDetection": [
                "detected": true,
                "type": "botDetection",
                "results": [
                    [
                        "detected": true,
                        "vendor": "google",
                        "challengeStatus": NSNull(),
                        "challengeType": "recaptcha"
                    ],
                    [
                        "detected": true,
                        "vendor": "hcaptcha",
                        "challengeStatus": NSNull(),
                        "challengeType": "hcaptcha"
                    ]
                ]
            ],
            "fraudDetection": [
                "detected": false,
                "type": "fraudDetection",
                "results": []
            ]
        ]
        let detectorData = DetectorData(from: inputDict)
        let flattened = detectorData.flattenedMetrics()

        XCTAssertEqual(flattened["botDetection.detected"], "true")
        XCTAssertNotNil(flattened["botDetection.results"])
        let botDetectionResults = flattened["botDetection.results"]!
        XCTAssertTrue(botDetectionResults.contains("google"))
        XCTAssertTrue(botDetectionResults.contains("hcaptcha"))
        XCTAssertTrue(botDetectionResults.contains("recaptcha"))
        XCTAssertTrue(botDetectionResults.contains("challengeType"))

        XCTAssertEqual(flattened["fraudDetection.detected"], "false")
        XCTAssertEqual(flattened["fraudDetection.results"], "")

        XCTAssertNil(flattened["botDetection.type"])
        XCTAssertNil(flattened["fraudDetection.type"])
    }
}
