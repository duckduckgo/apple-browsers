//
//  PixelExperimentKitTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import PixelExperimentKit
@testable import BrowserServicesKit
import PixelKit
import Combine

final class PixelExperimentKitTests: XCTestCase {
    var featureJson: Data = "{}".data(using: .utf8)!
    var mockPixelStore: MockExperimentActionPixelStore!
    var mockFeatureFlagger: MockFeatureFlagger!
    var firedEventSet = Set<String>()
    var firedEvent = [PixelKitEvent]()
    var firedFrequency = [PixelKit.Frequency]()
    var firedIncludeAppVersion = [Bool]()

    override func setUp() {
        super.setUp()
        mockPixelStore = MockExperimentActionPixelStore()
        mockFeatureFlagger = MockFeatureFlagger()
        PixelKit.configureExperimentKit(featureFlagger: mockFeatureFlagger, eventTracker: ExperimentEventTracker(store: mockPixelStore), fire: { event, frequency, includeAppVersion in
            self.firedEventSet.insert(event.name + "_" + (event.parameters?.toString() ?? ""))
            self.firedEvent.append(event)
            self.firedFrequency.append(frequency)
            self.firedIncludeAppVersion.append(includeAppVersion)
        })
    }

    override func tearDown() {
        mockPixelStore = nil
        mockFeatureFlagger = nil
        firedEvent = []
        firedFrequency = []
        firedIncludeAppVersion = []
    }

    func testfireExperimentEnrollmentPixelPixelSendsExpectedData() {
        // GIVEN
        let subfeatureID = "testSubfeature"
        let cohort = "A"
        let enrollmentDate = Date(timeIntervalSince1970: 0)
        let experimentData = ExperimentData(parentID: "parent", cohortID: cohort, enrollmentDate: enrollmentDate)
        let expectedEventName = "experiment_enroll_\(subfeatureID)_\(cohort)"
        let expectedParameters = ["enrollmentDate": enrollmentDate.toYYYYMMDDInET()]

        // WHEN
        PixelKit.fireExperimentEnrollmentPixel(subfeatureID: subfeatureID, experiment: experimentData)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueByNameAndParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindow() {
        // GIVEN

        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 5 days ago
        let conversionWindow = 3...3
        let value = "true"
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3",
            "value": value,
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueByNameAndParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithInvalidExperimentAndValidConversionWindow() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let conversionWindow = 3...7
        let value = String(Int.random(in: 1...100))
        mockFeatureFlagger.experiments = [:]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithValidExperimentAndBeforeConversionWindow() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        let conversionWindow = 8...11
        let value = "someValue"
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithValidExperimentAndAfterConversionWindow() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-12 * 24 * 60 * 60) // 12 days ago
        let conversionWindow = 8...11
        let value = "someValue"
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixel(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, value: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixel_WithValidExperimentAndConversionWindowAndValue1() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 5 days ago
        let conversionWindow = 3...7
        let value = 1
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-7",
            "value": String(value),
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixelIfThresholdReached(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, threshold: value)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueByNameAndParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixelWhenReachingNumberOfCalls_WithValidExperimentAndConversionWindowAndValue1() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 5 days ago
        let conversionWindow = 3...7
        let value = 1
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-7",
            "value": String(value),
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixelIfThresholdReached(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, threshold: value)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueByNameAndParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixelWhenReachingNumberOfCalls_WithValidExperimentAndConversionWindowAndValueN() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 5 days ago
        let conversionWindow = 3...7
        let value = Int.random(in: 1...100)
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-7",
            "value": String(value),
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN calling fire before expected number of calls
        for n in 1..<value {
            PixelKit.fireExperimentPixelIfThresholdReached(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, threshold: value)
            // THEN
            XCTAssertTrue(firedEvent.isEmpty)
            XCTAssertTrue(firedFrequency.isEmpty)
            XCTAssertTrue(firedIncludeAppVersion.isEmpty)
            XCTAssertEqual(mockPixelStore.store.count, 1)
            XCTAssertEqual(mockPixelStore.store.values.first, n)
        }

        // WHEN calling fire at the right number of calls
        PixelKit.fireExperimentPixelIfThresholdReached(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, threshold: value)

        // THEN
        XCTAssertEqual(firedEvent[0].name, expectedEventName)
        XCTAssertEqual(firedEvent[0].parameters, expectedParameters)
        XCTAssertEqual(firedFrequency[0], .uniqueByNameAndParameters)
        XCTAssertFalse(firedIncludeAppVersion[0])
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixelWhenReachingNumberOfCalls_WithInvalidExperimentAndValidConversionWindowAndValue1() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let conversionWindow = 3...7
        let value = Int.random(in: 1...100)
        mockFeatureFlagger.experiments = [:]

        // WHEN
        PixelKit.fireExperimentPixelIfThresholdReached(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, threshold: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixelWhenReachingNumberOfCalls_WithValidExperimentAndOutsideConversionWindowAndValueN() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        let conversionWindow = 8...11
        let value = 3
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]

        // WHEN
        PixelKit.fireExperimentPixelIfThresholdReached(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, threshold: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireExperimentPixelWhenReachingNumberOfCalls_WithValidExperimentAndAfterConversionWindowAndValueNAfterSomeCalledHappened() {
        // GIVEN
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 6 days ago
        let conversionWindow = 3...5
        let value = 3
        let experimentData = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate)
        mockFeatureFlagger.experiments = [subfeatureID: experimentData]
        let expectedEventName = "experiment_metrics_\(subfeatureID)_\(cohort)"
        let expectedParameters = [
            "metric": "someMetric",
            "conversionWindowDays": "3-5",
            "value": String(value),
            "enrollmentDate": enrollmentDate.toYYYYMMDDInET()
        ]
        let eventStoreKey = expectedEventName + "_" + expectedParameters.toString()
        mockPixelStore.store = [eventStoreKey: 2]

        // WHEN
        PixelKit.fireExperimentPixelIfThresholdReached(for: subfeatureID, metric: "someMetric", conversionWindowDays: conversionWindow, threshold: value)

        // THEN
        XCTAssertTrue(firedEvent.isEmpty)
        XCTAssertTrue(firedFrequency.isEmpty)
        XCTAssertTrue(firedIncludeAppVersion.isEmpty)
        XCTAssertEqual(mockPixelStore.store.count, 0)
    }

    func testFireSearchExperimentPixels_WithValue1() {
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate0 = Date()
        let enrollmentDate1 = Date().addingTimeInterval(-1 * 24 * 60 * 60) // 1 days ago
        let enrollmentDate2 = Date().addingTimeInterval(-2 * 24 * 60 * 60) // 2 days ago
        let enrollmentDate3 = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 3 days ago
        let enrollmentDate4 = Date().addingTimeInterval(-4 * 24 * 60 * 60) // 4 days ago
        let enrollmentDate5 = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        let enrollmentDate6 = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 6 days ago
        let enrollmentDate7 = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        let enrollmentDate8 = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        let experimentData0 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate0)
        let experimentData1 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate1)
        let experimentData2 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate2)
        let experimentData3 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate3)
        let experimentData4 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate4)
        let experimentData5 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate5)
        let experimentData6 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate6)
        let experimentData7 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate7)
        let experimentData8 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate8)

        mockFeatureFlagger.experiments = [subfeatureID: experimentData0]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 1) // Fires 1 0-0
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData1]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 1) // Fires 1 1-1
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData2]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 1) // Fires 1 2-2
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData3]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 1) // Fires 1 3-3
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData4]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 1) // Fires 1 4-4
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData5]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 2) // Fires 1 5-5 and 1 5-7
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData6]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 2) // Fires 1 6-6 and 1 5-7
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData7]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 2) // Fires 1 7-7 and 1 5-7
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData8]
        PixelKit.fireSearchExperimentPixels()
        XCTAssertEqual(firedEvent.count, 0) // Nothing
    }

    func testFireSearchExperimentPixels_WithValue4() {
        let subfeatureID = "credentialsSaving"
        let cohort = "control"
        let enrollmentDate4 = Date().addingTimeInterval(-4 * 24 * 60 * 60) // 4 days ago
        let enrollmentDate5 = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        let enrollmentDate7 = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days ago
        let enrollmentDate8 = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        let enrollmentDate15 = Date().addingTimeInterval(-15 * 24 * 60 * 60) // 15 days ago
        let enrollmentDate16 = Date().addingTimeInterval(-16 * 24 * 60 * 60) // 16 days ago
        let experimentData4 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate4)
        let experimentData5 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate5)
        let experimentData7 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate7)
        let experimentData8 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate8)
        let experimentData15 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate15)
        let experimentData16 = ExperimentData(parentID: "autofill", cohortID: cohort, enrollmentDate: enrollmentDate16)

        mockFeatureFlagger.experiments = [subfeatureID: experimentData4]
        PixelKit.fireSearchExperimentPixels() // Fires 1 4-4
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 1)
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 1)
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData5]
        PixelKit.fireSearchExperimentPixels() // Fires 1 5-5 + 1 5-7
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 2)
        PixelKit.fireSearchExperimentPixels() // Fires + 4 5-7
        XCTAssertEqual(firedEventSet.count, 3)
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData7]
        PixelKit.fireSearchExperimentPixels() // Fires 1 7-7 + 1 5-7
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 2)
        PixelKit.fireSearchExperimentPixels() // Fires + 4 5-7
        XCTAssertEqual(firedEventSet.count, 3)
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData8]
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 0)
        PixelKit.fireSearchExperimentPixels() // Fires 4 8-15
        XCTAssertEqual(firedEventSet.count, 1)
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData15]
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 0)
        PixelKit.fireSearchExperimentPixels() // Fires 4 8-15
        XCTAssertEqual(firedEventSet.count, 1)
        clearEvents()

        mockFeatureFlagger.experiments = [subfeatureID: experimentData16]
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 0)
        PixelKit.fireSearchExperimentPixels() // Nothing
        XCTAssertEqual(firedEventSet.count, 0)
        clearEvents()
    }

    func testFireSearchExperimentPixels_WithMultipleExperiments() {
        // GIVEN
        let subfeatureID1 = "credentialsSaving"
        let cohort1 = "control"
        let enrollmentDate1 = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 6 days ago
        let experimentData1 = ExperimentData(parentID: "autofill", cohortID: cohort1, enrollmentDate: enrollmentDate1)

        let subfeatureID2 = "inlineIconCredentials"
        let cohort2 = "test"
        let enrollmentDate2 = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let experimentData2 = ExperimentData(parentID: "autofill", cohortID: cohort2, enrollmentDate: enrollmentDate2)

        mockFeatureFlagger.experiments = [
            subfeatureID1: experimentData1,
            subfeatureID2: experimentData2
        ]

        // WHEN
        PixelKit.fireSearchExperimentPixels()

        // THEN
        // Verify pixel for the first experiment
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID1)_\(cohort1)"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.metricKey] == PixelKit.Constants.searchMetricValue
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "5-7"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "6"
            }
        )

        // Verify no pixel fired for the second experiment (outside conversion window)
        XCTAssertNotNil(mockPixelStore.store)
        XCTAssertFalse(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )

        // Verify no pixel fired that after 4 reps second experiment pixel is sent(outside conversion window)
        PixelKit.fireSearchExperimentPixels()
        PixelKit.fireSearchExperimentPixels()
        PixelKit.fireSearchExperimentPixels()
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )
    }

    func testFireAppRetentionExperimentPixels_WithMultipleExperiments() {
        // GIVEN
        let subfeatureID1 = "credentialsSaving"
        let cohort1 = "control"
        let enrollmentDate1 = Date().addingTimeInterval(-6 * 24 * 60 * 60) // 6 days ago
        let experimentData1 = ExperimentData(parentID: "autofill", cohortID: cohort1, enrollmentDate: enrollmentDate1)

        let subfeatureID2 = "inlineIconCredentials"
        let cohort2 = "test"
        let enrollmentDate2 = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let experimentData2 = ExperimentData(parentID: "autofill", cohortID: cohort2, enrollmentDate: enrollmentDate2)

        mockFeatureFlagger.experiments = [
            subfeatureID1: experimentData1,
            subfeatureID2: experimentData2
        ]

        // WHEN
        PixelKit.fireAppRetentionExperimentPixels()

        // THEN
        // Verify pixel for the first experiment
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID1)_\(cohort1)"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.metricKey] == PixelKit.Constants.appUseMetricValue
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "5-7"
            }
        )
        XCTAssertTrue(
            firedEvent.contains {
                $0.parameters?[PixelKit.Constants.conversionWindowDaysKey] == "6"
            }
        )

        // Verify no pixel fired for the second experiment (outside conversion window)
        XCTAssertNotNil(mockPixelStore.store)
        XCTAssertFalse(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )

        // Verify no pixel fired that after 4 reps second experiment pixel is sent(outside conversion window)
        PixelKit.fireAppRetentionExperimentPixels()
        PixelKit.fireAppRetentionExperimentPixels()
        PixelKit.fireAppRetentionExperimentPixels()
        XCTAssertTrue(
            firedEvent.contains {
                $0.name == "experiment_metrics_\(subfeatureID2)_\(cohort2)"
            }
        )
    }

    private func clearEvents() {
        firedEvent = []
        firedEventSet = []
        firedFrequency = []
        firedIncludeAppVersion = []
    }

}

class MockExperimentActionPixelStore: ExperimentActionPixelStore {

    var store: [String: Int] = [:]

    func removeObject(forKey defaultName: String) {
        store.removeValue(forKey: defaultName)
    }

    func integer(forKey defaultName: String) -> Int {
        return store[defaultName] ?? 0
    }

    func set(_ value: Int, forKey defaultName: String) {
        store[defaultName] = value
    }
}

class MockFeatureFlagger: FeatureFlagger {
    func resolveCohort<Flag>(for featureFlag: Flag, allowOverride: Bool) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        nil
    }

    var experiments: Experiments = [:]

    var internalUserDecider: any InternalUserDecider = MockInternalUserDecider()

    var localOverrides: (any BrowserServicesKit.FeatureFlagLocalOverriding)?

    func resolveCohort<Flag>(for featureFlag: Flag) -> (any FeatureFlagCohortDescribing)? where Flag: FeatureFlagDescribing {
        return nil
    }

    var allActiveExperiments: Experiments {
        return experiments
    }

    func isFeatureOn<Flag>(for featureFlag: Flag, allowOverride: Bool) -> Bool where Flag: FeatureFlagDescribing {
        return false
    }
}

final class MockInternalUserDecider: InternalUserDecider {
    var isInternalUser: Bool = false

    var isInternalUserPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool {
        return false
    }
}
