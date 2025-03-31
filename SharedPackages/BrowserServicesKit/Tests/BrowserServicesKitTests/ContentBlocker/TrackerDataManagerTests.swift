//
//  TrackerDataManagerTests.swift
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import CommonCrypto
import TrackerRadarKit
@testable import BrowserServicesKit
import WebKit

class TrackerDataManagerTests: XCTestCase {

    static let exampleTDS = """
        {
          "trackers": {
            "notreal.io": {
              "domain": "notreal.io",
              "default": "block",
              "owner": {
                "name": "Not Real LLC",
                "displayName": "Not Real",
                "privacyPolicy": "https://hermann.ai/privacy-en",
                "url": "http://hermann.ai"
              },
              "source": [
                "DDG"
              ],
              "prevalence": 0.002,
              "fingerprinting": 0,
              "cookies": 0.002,
              "performance": {
                "time": 1,
                "size": 1,
                "cpu": 1,
                "cache": 3
              },
              "categories": [
                "Ad Motivated Tracking",
                "Advertising",
                "Analytics",
                "Third-Party Analytics Marketing"
              ]
            }
          },
          "entities": {
            "Not Real": {
              "domains": [
                "notreal.io"
              ],
              "displayName": "Not Real",
              "prevalence": 0.666
            }
          },
          "domains": {
            "notreal.io": "Not Real"
          }
        }
        """

    func testWhenReloadCalledInitiallyThenDataSetIsEmbedded() {

        let exampleData = Self.exampleTDS.data(using: .utf8)!
        let embeddedDataProvider = MockEmbeddedDataProvider(data: exampleData,
                                                            etag: "embedded")

        XCTAssertEqual(TrackerDataManager(etag: nil,
                                          data: nil,
                                          embeddedDataProvider: embeddedDataProvider).reload(etag: nil,
                                                                                             data: nil),
                       TrackerDataManager.ReloadResult.embedded)
    }

    func testFindTrackerByUrl() {
        let exampleData = Self.exampleTDS.data(using: .utf8)!
        let embeddedDataProvider = MockEmbeddedDataProvider(data: exampleData,
                                                            etag: "embedded")

        let trackerDataManager = TrackerDataManager(etag: nil,
                                                    data: nil,
                                                    embeddedDataProvider: embeddedDataProvider)
        let tracker = trackerDataManager.embeddedData.tds.findTracker(forUrl: "http://notreal.io")
        XCTAssertNotNil(tracker)
        XCTAssertEqual("Not Real", tracker?.owner?.displayName)
    }

    func testFindEntityByName() {
        let exampleData = Self.exampleTDS.data(using: .utf8)!
        let embeddedDataProvider = MockEmbeddedDataProvider(data: exampleData,
                                                            etag: "embedded")

        let trackerDataManager = TrackerDataManager(etag: nil,
                                                    data: nil,
                                                    embeddedDataProvider: embeddedDataProvider)
        let entity = trackerDataManager.embeddedData.tds.findEntity(byName: "Not Real")
        XCTAssertNotNil(entity)
        XCTAssertEqual("Not Real", entity?.displayName)
    }

    func testFindEntityForHost() {
        let exampleData = Self.exampleTDS.data(using: .utf8)!
        let embeddedDataProvider = MockEmbeddedDataProvider(data: exampleData,
                                                            etag: "embedded")

        let trackerDataManager = TrackerDataManager(etag: nil,
                                                    data: nil,
                                                    embeddedDataProvider: embeddedDataProvider)

        let entity = trackerDataManager.embeddedData.tds.findEntity(forHost: "www.notreal.io")
        XCTAssertNotNil(entity)
        XCTAssertEqual("Not Real", entity?.displayName)
    }

    func testWhenDownloadedDataAvailableThenReloadUsesIt() {

        let exampleData = Self.exampleTDS.data(using: .utf8)!
        let embeddedDataProvider = MockEmbeddedDataProvider(data: exampleData,
                                                            etag: "embedded")

        let trackerDataManager = TrackerDataManager(etag: nil,
                                                    data: nil,
                                                    embeddedDataProvider: embeddedDataProvider)

        XCTAssertEqual(trackerDataManager.embeddedData.etag, "embedded")
        XCTAssertEqual(trackerDataManager.reload(etag: "new etag", data: exampleData),
                       TrackerDataManager.ReloadResult.downloaded)

        XCTAssertEqual(trackerDataManager.fetchedData?.etag, "new etag")
        XCTAssertNil(trackerDataManager.fetchedData?.tds.findEntity(byName: "Google LLC"))
        XCTAssertNotNil(trackerDataManager.fetchedData?.tds.findEntity(byName: "Not Real"))

    }
}
