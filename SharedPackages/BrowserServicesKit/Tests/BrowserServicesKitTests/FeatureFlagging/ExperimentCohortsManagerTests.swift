//
//  ExperimentCohortsManagerTests.swift
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
@testable import BrowserServicesKit

final class ExperimentCohortsManagerTests: XCTestCase {

    let cohort1 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort1", "weight": 1])!
    let cohort2 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort2", "weight": 0])!
    let cohort3 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort3", "weight": 2])!
    let cohort4 = PrivacyConfigurationData.Cohort(json: ["name": "Cohort4", "weight": 0])!

    var mockStore: MockExperimentDataStore!
    var experimentCohortsManager: ExperimentCohortsManager!

    let subfeatureName1 = "TestSubfeature1"
    var experimentData1: ExperimentData!

    let subfeatureName2 = "TestSubfeature2"
    var experimentData2: ExperimentData!

    let subfeatureName3 = "TestSubfeature3"
    var experimentData3: ExperimentData!

    let subfeatureName4 = "TestSubfeature4"
    var experimentData4: ExperimentData!

    var firedSubfeatureID: SubfeatureID?
    var firedExperimentData: ExperimentData?

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    override func setUp() {
        super.setUp()
        mockStore = MockExperimentDataStore()

        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore, fireCohortAssigned: {subfeatureID, experimentData in
                self.firedSubfeatureID = subfeatureID
                self.firedExperimentData = experimentData
            }
        )

        let expectedDate1 = Date()
        experimentData1 = ExperimentData(parentID: "TestParent", cohortID: cohort1.name, enrollmentDate: expectedDate1)

        let expectedDate2 = Date().addingTimeInterval(60)
        experimentData2 = ExperimentData(parentID: "TestParent", cohortID: cohort2.name, enrollmentDate: expectedDate2)

        let expectedDate3 = Date()
        experimentData3 = ExperimentData(parentID: "TestParent", cohortID: cohort3.name, enrollmentDate: expectedDate3)

        let expectedDate4 = Date().addingTimeInterval(60)
        experimentData4 = ExperimentData(parentID: "TestParent", cohortID: cohort4.name, enrollmentDate: expectedDate4)
    }

    override func tearDown() {
        mockStore = nil
        experimentCohortsManager = nil
        experimentData1 = nil
        experimentData2 = nil
        super.tearDown()
    }

    func testExperimentReturnAssignedExperiments() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]

        // WHEN
        let experiments = experimentCohortsManager.experiments

        // THEN
        XCTAssertEqual(experiments?.count, 2)
        XCTAssertEqual(experiments?[subfeatureName1], experimentData1)
        XCTAssertEqual(experiments?[subfeatureName2], experimentData2)
        XCTAssertNil(experiments?[subfeatureName3])
        XCTAssertNil(firedSubfeatureID)
        XCTAssertNil(firedExperimentData)
    }

    func testCohortReturnsCohortIDIfExistsForMultipleSubfeatures() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]

        // WHEN
        let result1 = experimentCohortsManager.resolveCohort(for: ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: [cohort1, cohort2]), allowCohortAssignment: false)
        let result2 = experimentCohortsManager.resolveCohort(for: ExperimentSubfeature(parentID: experimentData2.parentID, subfeatureID: subfeatureName2, cohorts: [cohort2, cohort3]), allowCohortAssignment: false)

        // THEN
        XCTAssertEqual(result1, experimentData1.cohortID)
        XCTAssertEqual(result2, experimentData2.cohortID)
        XCTAssertNil(firedSubfeatureID)
        XCTAssertNil(firedExperimentData)
    }

    func testCohortAssignIfEnabledWhenNoCohortExists() {
        // GIVEN
        mockStore.experiments = [:]
        let cohorts = [cohort1, cohort2]
        let experiment = ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: cohorts)

        // WHEN
        let result = experimentCohortsManager.resolveCohort(for: experiment, allowCohortAssignment: true)

        // THEN
        XCTAssertNotNil(result)
        XCTAssertEqual(result, experimentData1.cohortID)
        XCTAssertEqual(firedSubfeatureID, subfeatureName1)
        XCTAssertEqual(firedExperimentData?.cohortID, experimentData1.cohortID)
        XCTAssertEqual(firedExperimentData?.parentID, experimentData1.parentID)
        XCTAssertEqual(firedExperimentData?.enrollmentDate.daySinceReferenceDate, experimentData1.enrollmentDate.daySinceReferenceDate)
    }

    func testCohortDoesNotAssignIfAssignIfEnabledIsFalse() {
        // GIVEN
        mockStore.experiments = [:]
        let cohorts = [cohort1, cohort2]
        let experiment = ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: cohorts)

        // WHEN
        let result = experimentCohortsManager.resolveCohort(for: experiment, allowCohortAssignment: false)

        // THEN
        XCTAssertNil(result)
        XCTAssertNil(firedSubfeatureID)
        XCTAssertNil(firedExperimentData)
    }

    func testCohortDoesNotAssignIfAssignIfEnabledIsTrueButNoCohortsAvailable() {
        // GIVEN
        mockStore.experiments = [:]
        let experiment = ExperimentSubfeature(parentID: "TestParent", subfeatureID: "NonExistentSubfeature", cohorts: [])

        // WHEN
        let result = experimentCohortsManager.resolveCohort(for: experiment, allowCohortAssignment: true)

        // THEN
        XCTAssertNil(result)
        XCTAssertNil(firedSubfeatureID)
        XCTAssertNil(firedExperimentData)
    }

    func testCohortReassignsCohortIfAssignedCohortDoesNotExistAndAssignIfEnabledIsTrue() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1]

        // WHEN
        let result1 = experimentCohortsManager.resolveCohort(for: ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: [cohort2, cohort3]), allowCohortAssignment: true)

        // THEN
        XCTAssertEqual(result1, experimentData3.cohortID)
        XCTAssertEqual(firedSubfeatureID, subfeatureName1)
        XCTAssertEqual(firedExperimentData?.cohortID, experimentData3.cohortID)
        XCTAssertEqual(firedExperimentData?.parentID, experimentData3.parentID)
        XCTAssertEqual(firedExperimentData?.enrollmentDate.daySinceReferenceDate, experimentData3.enrollmentDate.daySinceReferenceDate)
    }

    func testCohortDoesNotReassignsCohortIfAssignedCohortDoesNotExistAndAssignIfEnabledIsTrue() {
        // GIVEN
        mockStore.experiments = [subfeatureName1: experimentData1]

        // WHEN
        let result1 = experimentCohortsManager.resolveCohort(for: ExperimentSubfeature(parentID: experimentData1.parentID, subfeatureID: subfeatureName1, cohorts: [cohort2, cohort3]), allowCohortAssignment: false)

        // THEN
        XCTAssertNil(result1)
        XCTAssertNil(firedSubfeatureID)
        XCTAssertNil(firedExperimentData)
    }

    func testCohortAssignsBasedOnWeight() {
        // GIVEN
        let experiment = ExperimentSubfeature(parentID: experimentData3.parentID, subfeatureID: subfeatureName3, cohorts: [cohort3, cohort4])

        let randomizer: (Range<Double>) -> Double = { range in
            return 1.5
        }

        experimentCohortsManager = ExperimentCohortsManager(
            store: mockStore,
            randomizer: randomizer, fireCohortAssigned: { _, _ in }
        )

        // WHEN
        let result = experimentCohortsManager.resolveCohort(for: experiment, allowCohortAssignment: true)

        // THEN
        XCTAssertEqual(result, experimentData3.cohortID)
    }
}

class MockExperimentDataStore: ExperimentsDataStoring {
    var experiments: Experiments?
}
