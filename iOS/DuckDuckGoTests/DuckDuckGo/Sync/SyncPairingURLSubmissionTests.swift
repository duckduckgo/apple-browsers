//
//  SyncPairingURLSubmissionTests.swift
//  DuckDuckGo
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
import FeatureFlags_iOS
import XCTest
@testable import DuckDuckGo

final class SyncPairingURLSubmissionTests: XCTestCase {

    func testAddressBarVariantsOpenTheMatchingDestinationWithEitherURLPredictor() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.syncPairingUrl])
        for useUnifiedLogic in [false, true] {
            for (host, destination) in [("duck.com", SyncPairingURL.duckCom), ("duck.ai", .duckAI)] {
                for input in [host + "/pair", " " + host + "/PAIR/ ", "http://www." + host + "/pair",
                              "https://" + host + "/pair?", host + "/pair#code2=untrusted", host + "/pair?code2=untrusted"] {
                    XCTAssertEqual(SyncPairingURL(addressBarQuery: input, syncService: MockDDGSyncing(), featureFlagger: flagger, useUnifiedLogic: useUnifiedLogic),
                                   destination, input)
                }
            }
        }
    }

    func testInterceptionRespondsToFlagChangesWithoutRestarting() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        for enabled in [false, true, false, true] {
            flagger.enabledFeatureFlags = enabled ? [.syncPairingUrl] : []
            XCTAssertEqual(SyncPairingURL(addressBarQuery: "duck.ai/pair#code2=untrusted", syncService: MockDDGSyncing(), featureFlagger: flagger, useUnifiedLogic: false),
                           enabled ? .duckAI : nil)
        }
    }

    func testPairingAvailabilityChangesWhetherAddressBarURLsAreIntercepted() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.syncPairingUrl])
        let syncService = MockDDGSyncing()
        let availability: [(SyncFeatureFlags, Bool, Bool)] = [
            (.unavailable, false, false),
            (.level0ShowSync, false, false),
            (.level1AllowDataSyncing, false, false),
            (.level2AllowSetupFlows, true, false),
            (.all, true, true),
            (.unavailable, false, false)
        ]
        for (flags, interceptsActive, interceptsInactive) in availability {
            syncService.featureFlags = flags
            for (state, intercepts) in [(SyncAuthState.active, interceptsActive), (.inactive, interceptsInactive)] {
                syncService.authState = state
                for (host, destination) in [("duck.com", SyncPairingURL.duckCom), ("duck.ai", .duckAI)] {
                    XCTAssertEqual(SyncPairingURL(addressBarQuery: host + "/pair", syncService: syncService,
                                                 featureFlagger: flagger, useUnifiedLogic: false),
                                   intercepts ? destination : nil, "\(host), \(state), \(flags)")
                }
            }
        }
    }

    func testOtherQueriesAndLegacyPairingLinksAreNotIntercepted() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.syncPairingUrl])
        for input in ["sync my bookmarks", "duck.com/pair/extra", "duck.ai/pair/extra", "duckduckgo.com/pair",
                      "https://duckduckgo.com/sync/pairing/#&code2=legacy", "https://duck.com.evil.com/pair"] {
            XCTAssertNil(SyncPairingURL(addressBarQuery: input, syncService: MockDDGSyncing(), featureFlagger: flagger, useUnifiedLogic: false), input)
        }
    }
}
