//
//  AutofillExtensionPromotionManagerTests.swift
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
@testable import DuckDuckGo
import Persistence
@testable import PersistenceTestingUtils

final class AutofillExtensionPromotionManagerTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockKeyValueStore: ThrowingKeyValueStoring!
    private var manager: AutofillExtensionPromotionManager!

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockFeatureFlagger = MockFeatureFlagger()
        mockKeyValueStore = try MockKeyValueFileStore(throwOnInit: nil)
        manager = AutofillExtensionPromotionManager(featureFlagger: mockFeatureFlagger, keyValueStore: mockKeyValueStore)
    }

    override func tearDownWithError() throws {
        mockFeatureFlagger = nil
        mockKeyValueStore = nil
        manager = nil

        try super.tearDownWithError()
    }
}
