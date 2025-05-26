//
//  KeyValueFileStorePerformanceTests.swift
//  DuckDuckGo
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
import DuckDuckGo
import Persistence

class KeyValueFileStorePerformanceTests: XCTestCase {

    static let tempDir: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override class func setUp() {
        super.setUp()

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Could not prepare test DIR")
        }
    }

    override class func tearDown() {
        super.setUp()

        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            XCTFail("Could not cleanup test DIR")
        }
    }

    func makeTabsModel(count: Int) -> TabsModel {

        var tabs = [Tab]()
        for i in 1...count {

            let tab = Tab(uid: "\(i)",
                          link: .init(title: UUID().uuidString, url: URL(string: "https://example.com")!),
                          viewed: true)

            tabs.append(tab)
        }

        return TabsModel(tabs: tabs, currentIndex: 0, desktop: false)
    }

    func makeBigDict(count: Int) -> [String: [String: String]] {
        let nested = 5

        var dict = [String: [String: String]]()
        for i in 1...count {

            var subDict = [String: String]()
            for n in 1...nested {
                subDict["\(n)"] = UUID().uuidString
            }
            dict[UUID().uuidString] = subDict
        }
        return dict
    }

    func testUserDefaultsData() throws {
        let ud = UserDefaults.standard

        let key = "KeyValueFileStorePerformanceTests"

        // warm up to measure consecutive storing
        let model = makeTabsModel(count: 1000)
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        ud.set(data, forKey: key)

        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {

            do {
                let model = makeTabsModel(count: 1000)
                let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)

                startMeasuring()
                ud.set(data, forKey: key)
                stopMeasuring()
            } catch {
                stopMeasuring()
                XCTFail("Could not store data")
            }
        }
    }

    func testKeyValueStoreData() throws {

        let name = UUID().uuidString
        let key = "KeyValueFileStorePerformanceTests"

        let kvs = KeyValueFileStore(location: Self.tempDir, name: name)

        // warm up to measure consecutive storing
        let model = makeTabsModel(count: 1000)
        let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
        try kvs.set(data, forKey: key)

        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {

            do {
                let model = makeTabsModel(count: 1000)
                let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)

                startMeasuring()
                try kvs.set(data, forKey: key)
                stopMeasuring()
            } catch {
                stopMeasuring()
                XCTFail("Could not store data")
            }
        }
    }

    func testUserDefaultsDict() throws {

        let ud = UserDefaults.standard
        let key = "KeyValueFileStorePerformanceTests"
        ud.set(Data(), forKey: key)

        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {

            let dict = makeBigDict(count: 5000)

            startMeasuring()
            ud.set(dict, forKey: key)
            stopMeasuring()
        }
    }

    func testKeyValueStoreDict() throws {

        let name = UUID().uuidString
        let key = "KeyValueFileStorePerformanceTests"

        let kvs = KeyValueFileStore(location: Self.tempDir, name: name)
        try kvs.set(Data(), forKey: key)

        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {

            let dict = makeBigDict(count: 5000)

            do {
                startMeasuring()
                try kvs.set(dict, forKey: key)
                stopMeasuring()
            } catch {
                stopMeasuring()
                XCTFail("Could not store data")
            }

        }
    }
}
