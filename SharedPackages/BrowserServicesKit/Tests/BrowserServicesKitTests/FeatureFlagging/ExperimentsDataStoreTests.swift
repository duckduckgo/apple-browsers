//
//  ExperimentsDataStoreTests.swift
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

final class ExperimentsDataStoreTests: XCTestCase {

    let subfeatureName1 = "TestSubfeature1"
    var expectedDate1: Date!
    var experimentData1: ExperimentData!

    let subfeatureName2 = "TestSubfeature2"
    var expectedDate2: Date!
    var experimentData2: ExperimentData!

    var mockDataStore: MockLocalDataStore!
    var experimentsDataStore: ExperimentsDataStore!
    let testExperimentKey = "ExperimentsData"

    override func setUp() {
        super.setUp()
        mockDataStore = MockLocalDataStore()
        experimentsDataStore = ExperimentsDataStore(localDataStoring: mockDataStore)
    }

    override func tearDown() {
        mockDataStore = nil
        experimentsDataStore = nil
        super.tearDown()
    }

    func testExperimentsGetReturnsDecodedExperiments() {
        // GIVEN
        let experimentData1 = ExperimentData(parentID: "parent", cohortID: "TestCohort1", enrollmentDate: Date())
        let experimentData2 = ExperimentData(parentID: "parent", cohortID: "TestCohort2", enrollmentDate: Date())
        let experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let encodedData = try? encoder.encode(experiments)
        mockDataStore.data = encodedData

        // WHEN
        let result = experimentsDataStore.experiments

        // THEN
        let timeDifference1 = abs(experimentData1.enrollmentDate.timeIntervalSince(result?[subfeatureName1]?.enrollmentDate ?? Date()))
        let timeDifference2 = abs(experimentData2.enrollmentDate.timeIntervalSince(result?[subfeatureName2]?.enrollmentDate ?? Date()))
        XCTAssertEqual(result?[subfeatureName1]?.cohortID, experimentData1.cohortID)
        XCTAssertLessThanOrEqual(timeDifference1, 1.0)

        XCTAssertEqual(result?[subfeatureName2]?.cohortID, experimentData2.cohortID)
        XCTAssertLessThanOrEqual(timeDifference2, 1.0)
    }

    func testExperimentsSetEncodesAndStoresData() throws {
        // GIVEN
        let experimentData1 = ExperimentData(parentID: "parent", cohortID: "TestCohort1", enrollmentDate: Date())
        let experimentData2 = ExperimentData(parentID: "parent2", cohortID: "TestCohort2", enrollmentDate: Date())
        let experiments = [subfeatureName1: experimentData1, subfeatureName2: experimentData2]

        // WHEN
        experimentsDataStore.experiments = experiments

        // THEN
        let storedData = try XCTUnwrap(mockDataStore.data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decodedExperiments = try? decoder.decode(Experiments.self, from: storedData)
        let timeDifference1 = abs(experimentData1.enrollmentDate.timeIntervalSince(decodedExperiments?[subfeatureName1]?.enrollmentDate ?? Date()))
        let timeDifference2 = abs(experimentData2.enrollmentDate.timeIntervalSince(decodedExperiments?[subfeatureName2]?.enrollmentDate ?? Date()))
        XCTAssertEqual(decodedExperiments?[subfeatureName1]?.cohortID, experimentData1.cohortID)
        XCTAssertEqual(decodedExperiments?[subfeatureName1]?.parentID, experimentData1.parentID)
        XCTAssertLessThanOrEqual(timeDifference1, 1.0)
        XCTAssertEqual(decodedExperiments?[subfeatureName2]?.cohortID, experimentData2.cohortID)
        XCTAssertEqual(decodedExperiments?[subfeatureName2]?.parentID, experimentData2.parentID)
        XCTAssertLessThanOrEqual(timeDifference2, 1.0)
    }
}

class MockLocalDataStore: LocalDataStoring {
    var data: Data?

    func data(forKey defaultName: String) -> Data? {
        return data
    }

    func set(_ value: Any?, forKey defaultName: String) {
        data = value as? Data
    }
}
