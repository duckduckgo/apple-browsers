//
//  ContextualUnifiedToggleInputFeatureTests.swift
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
import Core
@testable import DuckDuckGo

final class ContextualUnifiedToggleInputFeatureTests: XCTestCase {

    // The presubmission contextual UTI is available only when BOTH the UTI itself is available
    // (iPhone + grant-gated) AND the contextual feature flag is on. Exercise the full 2x2.

    func test_isAvailable_trueOnlyWhenUTIAvailableAndFlagOn() {
        XCTAssertTrue(makeFeature(utiAvailable: true, flagOn: true).isAvailable)
    }

    func test_isAvailable_falseWhenFlagOff() {
        XCTAssertFalse(makeFeature(utiAvailable: true, flagOn: false).isAvailable)
    }

    func test_isAvailable_falseWhenUTIUnavailable() {
        XCTAssertFalse(makeFeature(utiAvailable: false, flagOn: true).isAvailable)
    }

    func test_isAvailable_falseWhenNeither() {
        XCTAssertFalse(makeFeature(utiAvailable: false, flagOn: false).isAvailable)
    }

    // MARK: - Helpers

    private func makeFeature(utiAvailable: Bool, flagOn: Bool) -> ContextualUnifiedToggleInputFeature {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: flagOn ? [.aiChatContextualUnifiedToggleInput] : [])
        return ContextualUnifiedToggleInputFeature(
            featureFlagger: flagger,
            unifiedToggleInputFeature: MockUnifiedToggleInputFeatureProviding(isAvailable: utiAvailable)
        )
    }
}

private struct MockUnifiedToggleInputFeatureProviding: UnifiedToggleInputFeatureProviding {
    let isAvailable: Bool
    var isToggleHiddenOnDuckAITab: Bool = false
}
