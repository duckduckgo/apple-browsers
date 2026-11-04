//
//  AIBoundaryNavigationDecisionTests.swift
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

import XCTest
@testable import DuckDuckGo

final class AIBoundaryNavigationDecisionTests: XCTestCase {

    // MARK: - Programmatic navigation

    func testProgrammaticNavigation_featureOff_alwaysLoadsInPlace() {
        for currentIsAI in [true, false] {
            for currentHasContent in [true, false] {
                for targetIsAI in [true, false] {
                    let decision = AIBoundaryNavigationDecision.forProgrammaticNavigation(
                        currentIsAI: currentIsAI,
                        currentHasContent: currentHasContent,
                        targetIsAI: targetIsAI,
                        unifiedToggleInputAvailable: false
                    )
                    XCTAssertEqual(decision, .loadInPlace,
                                   "feature-off should always load in place; currentIsAI=\(currentIsAI) currentHasContent=\(currentHasContent) targetIsAI=\(targetIsAI)")
                }
            }
        }
    }

    func testProgrammaticNavigation_emptyTab_alwaysLoadsInPlace() {
        for currentIsAI in [true, false] {
            for targetIsAI in [true, false] {
                let decision = AIBoundaryNavigationDecision.forProgrammaticNavigation(
                    currentIsAI: currentIsAI,
                    currentHasContent: false,
                    targetIsAI: targetIsAI,
                    unifiedToggleInputAvailable: true
                )
                XCTAssertEqual(decision, .loadInPlace,
                               "empty NTP tab should always load in place; currentIsAI=\(currentIsAI) targetIsAI=\(targetIsAI)")
            }
        }
    }

    func testProgrammaticNavigation_webToWeb_loadsInPlace() {
        let decision = AIBoundaryNavigationDecision.forProgrammaticNavigation(
            currentIsAI: false,
            currentHasContent: true,
            targetIsAI: false,
            unifiedToggleInputAvailable: true
        )
        XCTAssertEqual(decision, .loadInPlace)
    }

    func testProgrammaticNavigation_chatToChat_loadsInPlace() {
        let decision = AIBoundaryNavigationDecision.forProgrammaticNavigation(
            currentIsAI: true,
            currentHasContent: true,
            targetIsAI: true,
            unifiedToggleInputAvailable: true
        )
        XCTAssertEqual(decision, .loadInPlace)
    }

    func testProgrammaticNavigation_webToChat_opensInNewTab() {
        let decision = AIBoundaryNavigationDecision.forProgrammaticNavigation(
            currentIsAI: false,
            currentHasContent: true,
            targetIsAI: true,
            unifiedToggleInputAvailable: true
        )
        XCTAssertEqual(decision, .openInNewTab)
    }

    func testProgrammaticNavigation_chatToWeb_opensInNewTab() {
        let decision = AIBoundaryNavigationDecision.forProgrammaticNavigation(
            currentIsAI: true,
            currentHasContent: true,
            targetIsAI: false,
            unifiedToggleInputAvailable: true
        )
        XCTAssertEqual(decision, .openInNewTab)
    }

    // MARK: - Same-frame link taps

    func testSameFrameLinkTap_webToWeb_loadsInPlace() {
        for featureOn in [true, false] {
            let decision = AIBoundaryNavigationDecision.forSameFrameLinkTap(
                currentIsAI: false,
                targetIsAI: false,
                unifiedToggleInputAvailable: featureOn
            )
            XCTAssertEqual(decision, .loadInPlace, "web→web should load in place regardless of feature flag (featureOn=\(featureOn))")
        }
    }

    func testSameFrameLinkTap_chatToChat_loadsInPlace() {
        for featureOn in [true, false] {
            let decision = AIBoundaryNavigationDecision.forSameFrameLinkTap(
                currentIsAI: true,
                targetIsAI: true,
                unifiedToggleInputAvailable: featureOn
            )
            XCTAssertEqual(decision, .loadInPlace, "chat→chat should load in place regardless of feature flag (featureOn=\(featureOn))")
        }
    }

    func testSameFrameLinkTap_chatToWeb_opensInNewTab_evenWhenFeatureOff() {
        let decision = AIBoundaryNavigationDecision.forSameFrameLinkTap(
            currentIsAI: true,
            targetIsAI: false,
            unifiedToggleInputAvailable: false
        )
        XCTAssertEqual(decision, .openInNewTab,
                       "chat→web link taps must always intercept so Duck.ai tabs survive outbound links")
    }

    func testSameFrameLinkTap_chatToWeb_opensInNewTab_whenFeatureOn() {
        let decision = AIBoundaryNavigationDecision.forSameFrameLinkTap(
            currentIsAI: true,
            targetIsAI: false,
            unifiedToggleInputAvailable: true
        )
        XCTAssertEqual(decision, .openInNewTab)
    }

    func testSameFrameLinkTap_webToChat_loadsInPlace_whenFeatureOff() {
        let decision = AIBoundaryNavigationDecision.forSameFrameLinkTap(
            currentIsAI: false,
            targetIsAI: true,
            unifiedToggleInputAvailable: false
        )
        XCTAssertEqual(decision, .loadInPlace,
                       "web→chat must keep legacy in-place behavior when unified input is off")
    }

    func testSameFrameLinkTap_webToChat_opensInNewTab_whenFeatureOn() {
        let decision = AIBoundaryNavigationDecision.forSameFrameLinkTap(
            currentIsAI: false,
            targetIsAI: true,
            unifiedToggleInputAvailable: true
        )
        XCTAssertEqual(decision, .openInNewTab)
    }
}
