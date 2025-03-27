//
//  MaliciousSiteProtectionEmbeddedDataProviderTest.swift
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
import Foundation
import XCTest

@testable import MaliciousSiteProtection

class MaliciousSiteProtectionEmbeddedDataProviderTest: XCTestCase {

    struct TestEmbeddedDataProvider: MaliciousSiteProtection.EmbeddedDataProviding {
        func revision(for dataType: MaliciousSiteProtection.DataManager.StoredDataType) -> Int {
            0
        }

        func url(for dataType: MaliciousSiteProtection.DataManager.StoredDataType) -> URL {
            switch dataType {
            case .filterSet(let key):
                Bundle.module.url(forResource: "\(key.threatKind)FilterSet", withExtension: "json")!
            case .hashPrefixSet(let key):
                Bundle.module.url(forResource: "\(key.threatKind)HashPrefixes", withExtension: "json")!
            }
        }

        func hash(for dataType: MaliciousSiteProtection.DataManager.StoredDataType) -> String {
            switch dataType {
            case .filterSet(let key):
                switch key.threatKind {
                case .phishing:
                    "4fd2868a4f264501ec175ab866504a2a96c8d21a3b5195b405a4a83b51eae504"
                case .malware:
                    "7f80bcae89250c4ecc4ed91b5a4c3a09fe6f098622369f2f46a8ab69023a7683"
                case .scam:
                    ""
                }
            case .hashPrefixSet(let key):
                switch key.threatKind {
                case .phishing:
                    "21b047a9950fcaf86034a6b16181e18815cb8d276386d85c8977ca8c5f8aa05f"
                case .malware:
                    "ef31819296d83136cdb131e877e08fd120571d4c82512ba8c3eb964885ec07bc"
                case .scam:
                    ""
                }
            }
        }
    }

    func testDataProviderLoadsJSON() {
        let dataProvider = TestEmbeddedDataProvider()
        let expectedFilter = Filter(hash: "e4753ddad954dafd4ff4ef67f82b3c1a2db6ef4a51bda43513260170e558bd13", regex: "(?i)^https?\\:\\/\\/privacy-test-pages\\.site(?:\\:(?:80|443))?\\/security\\/badware\\/phishing\\.html$")
        XCTAssertTrue(dataProvider.loadDataSet(for: .filterSet(threatKind: .phishing)).contains(expectedFilter))
        XCTAssertTrue(dataProvider.loadDataSet(for: .hashPrefixes(threatKind: .phishing)).contains("012db806"))
    }

}
