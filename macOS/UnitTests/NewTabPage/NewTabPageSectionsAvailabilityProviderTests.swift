//
//  NewTabPageSectionsAvailabilityProviderTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class NewTabPageSectionsAvailabilityProviderTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var provider: NewTabPageSectionsAvailabilityProvider!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        featureFlagger = nil
        provider = nil
        super.tearDown()
    }

    func testIsOmnibarAvailable_WhenFeatureFlagIsOn_ReturnsTrue() {
        featureFlagger.enabledFeatureFlags = [.newTabPageOmnibar]
        provider = NewTabPageSectionsAvailabilityProvider(featureFlagger: featureFlagger)

        XCTAssertTrue(provider.isOmnibarAvailable)
    }

    func testIsOmnibarAvailable_WhenFeatureFlagIsOff_ReturnsFalse() {
        featureFlagger.enabledFeatureFlags = []
        provider = NewTabPageSectionsAvailabilityProvider(featureFlagger: featureFlagger)

        XCTAssertFalse(provider.isOmnibarAvailable)
    }

}
