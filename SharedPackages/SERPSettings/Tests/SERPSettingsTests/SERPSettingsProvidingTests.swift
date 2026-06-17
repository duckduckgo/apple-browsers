//
//  SERPSettingsProvidingTests.swift
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

import Persistence
import PersistenceTestingUtils
import XCTest

@testable import SERPSettings

final class SERPSettingsProvidingTests: XCTestCase {

    var mockKeyValueStore: MockKeyValueFileStore!
    var provider: MockSERPSettingsProvider!

    override func setUp() async throws {
        try await super.setUp()
        mockKeyValueStore = MockKeyValueFileStore()
        provider = MockSERPSettingsProvider(keyValueStore: mockKeyValueStore)
    }

    override func tearDown() async throws {
        provider = nil
        mockKeyValueStore = nil
        try await super.tearDown()
    }

    // MARK: - Defaults when absent

    func testSearchAssistFrequency_returnsDefault_whenKeyAbsent() {
        XCTAssertEqual(provider.searchAssistFrequency, .sometimes)
        XCTAssertNil(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey))
    }

    func testHideAIGeneratedImages_returnsDefault_whenKeyAbsent() {
        XCTAssertFalse(provider.hideAIGeneratedImages)
        XCTAssertNil(provider.serpSettingValue(forKey: SERPSettingsConstants.hideAIGeneratedImagesKey))
    }

    // MARK: - Persist and read

    func testSettingSearchAssistFrequency_persistsAndReadsBack() {
        provider.searchAssistFrequency = .often
        XCTAssertEqual(provider.searchAssistFrequency, .often)
        XCTAssertEqual(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey), "3")
    }

    func testSettingHideAIGeneratedImages_persistsRawEncoding() {
        provider.hideAIGeneratedImages = true
        XCTAssertTrue(provider.hideAIGeneratedImages)
        XCTAssertEqual(provider.serpSettingValue(forKey: SERPSettingsConstants.hideAIGeneratedImagesKey), "1")
    }

    // MARK: - Merge does not clobber siblings

    func testMergeWrite_preservesSiblingKey() {
        provider.searchAssistFrequency = .often   // kbe "3"
        provider.hideAIGeneratedImages = true      // kbj "1"

        XCTAssertEqual(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey), "3")
        XCTAssertEqual(provider.serpSettingValue(forKey: SERPSettingsConstants.hideAIGeneratedImagesKey), "1")
        XCTAssertEqual(provider.searchAssistFrequency, .often)
        XCTAssertTrue(provider.hideAIGeneratedImages)
    }

    // MARK: - Setting the default removes the key

    func testSettingSearchAssistToDefault_removesKey() {
        provider.searchAssistFrequency = .often
        XCTAssertNotNil(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey))

        provider.searchAssistFrequency = .sometimes // the default
        XCTAssertNil(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey))
        XCTAssertEqual(provider.searchAssistFrequency, .sometimes)
    }

    func testSettingHideAIGeneratedImagesToDefault_removesKey() {
        provider.hideAIGeneratedImages = true
        XCTAssertNotNil(provider.serpSettingValue(forKey: SERPSettingsConstants.hideAIGeneratedImagesKey))

        provider.hideAIGeneratedImages = false // the default (show)
        XCTAssertNil(provider.serpSettingValue(forKey: SERPSettingsConstants.hideAIGeneratedImagesKey))
        XCTAssertFalse(provider.hideAIGeneratedImages)
    }

    func testSettingDefaultDoesNotRemoveSibling() {
        provider.searchAssistFrequency = .often
        provider.hideAIGeneratedImages = true

        provider.hideAIGeneratedImages = false // default, removes kbj only
        XCTAssertNil(provider.serpSettingValue(forKey: SERPSettingsConstants.hideAIGeneratedImagesKey))
        XCTAssertEqual(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey), "3")
    }

    // MARK: - Low-level accessors

    func testSetSERPSetting_nilRemovesKey() {
        provider.setSERPSetting("3", forKey: SERPSettingsConstants.searchAssistKey)
        XCTAssertEqual(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey), "3")

        provider.setSERPSetting(nil, forKey: SERPSettingsConstants.searchAssistKey)
        XCTAssertNil(provider.serpSettingValue(forKey: SERPSettingsConstants.searchAssistKey))
    }

    func testUnrecognizedRawValue_fallsBackToDefault() {
        provider.setSERPSetting("99", forKey: SERPSettingsConstants.searchAssistKey)
        XCTAssertEqual(provider.searchAssistFrequency, .sometimes)

        provider.setSERPSetting("0", forKey: SERPSettingsConstants.hideAIGeneratedImagesKey)
        XCTAssertFalse(provider.hideAIGeneratedImages)
    }
}
