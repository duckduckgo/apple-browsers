//
//  SyncPairingURLSubmissionTests.swift
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

import DDGSync
import FeatureFlags_macOS
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class SyncPairingURLSubmissionTests: XCTestCase {

    func testTypedAndPastedVariantsMatchWithEitherURLPredictor() {
        let flagger = MockFeatureFlagger()
        for unifiedPrediction in [false, true] {
            flagger.enabledFeatureFlags = unifiedPrediction ? [.syncPairingUrl, .unifiedURLPredictor] : [.syncPairingUrl]
            for (host, destination) in [("duck.com", SyncPairingURL.duckCom), ("duck.ai", .duckAI)] {
                for input in [host + "/pair", " " + host + "/PAIR/ ", "http://www." + host + "/pair",
                              "https://" + host + "/pair?", host + "/pair?ref=test", host + "/pair#code2=untrusted",
                              host + "/pair?code2=untrusted"] {
                    XCTAssertEqual(SyncPairingURL(addressBarQuery: input, isSuggestionSelected: false, featureFlagger: flagger), destination, input)
                }
            }
        }
    }

    func testSelectedSuggestionsDoNotOpenNativePairing() {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.syncPairingUrl]
        for input in ["duck.com/pair", "https://duck.ai/pair#code2=untrusted"] {
            XCTAssertNil(SyncPairingURL(addressBarQuery: input, isSuggestionSelected: true, featureFlagger: flagger))
            XCTAssertNotNil(SyncPairingURL(addressBarQuery: input, isSuggestionSelected: false, featureFlagger: flagger))
        }
    }

    func testInterceptionRespondsToFlagChanges() {
        let flagger = MockFeatureFlagger()
        for enabled in [false, true, false, true] {
            flagger.enabledFeatureFlags = enabled ? [.syncPairingUrl] : []
            XCTAssertEqual(SyncPairingURL(addressBarQuery: "duck.ai/pair", isSuggestionSelected: false, featureFlagger: flagger),
                           enabled ? .duckAI : nil)
        }
    }

    func testOtherURLsAndLegacyPairingLinksAreNotIntercepted() {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.syncPairingUrl]
        for input in ["sync my bookmarks", "duck.com/pair/extra", "https://duck.ai/pair//", "https://sub.duck.com/pair",
                      "https://duck.com.evil.com/pair", "https://duckduckgo.com/sync/pairing/#&code2=legacy"] {
            XCTAssertNil(SyncPairingURL(addressBarQuery: input, isSuggestionSelected: false, featureFlagger: flagger), input)
        }
    }
}
