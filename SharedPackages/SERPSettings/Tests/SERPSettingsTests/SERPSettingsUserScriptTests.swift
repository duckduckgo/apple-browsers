//
//  SERPSettingsUserScriptTests.swift
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
import WebKit
import Persistence
import PersistenceTestingUtils
import UserScript
@testable import SERPSettings

@MainActor
final class SERPSettingsUserScriptTests: XCTestCase {

    var mockKeyValueStore: MockKeyValueFileStore!
    var mockProvider: MockSERPSettingsProvider!
    var mockDelegate: MockSERPSettingsDelegate!
    var userScript: SERPSettingsUserScript!

    override func setUp() async throws {
        try await super.setUp()

        mockKeyValueStore = try MockKeyValueFileStore()
        mockProvider = MockSERPSettingsProvider(keyValueStore: mockKeyValueStore)
        mockDelegate = MockSERPSettingsDelegate()
        userScript = SERPSettingsUserScript(serpSettingsProviding: mockProvider)
        userScript.delegate = mockDelegate
    }

    override func tearDown() async throws {
        mockProvider.reset()
        mockDelegate.reset()
        userScript = nil
        mockDelegate = nil
        mockProvider = nil
        mockKeyValueStore = nil
        try await super.tearDown()
    }

    // MARK: - getNativeSettings message tests

    func testGetNativeSettingsIsNil_whenFeatureFlagIsOffAndDataIsAvailable() async throws {
        // Given - Feature flag is OFF but data exists
        mockProvider.mockIsSERPSettingsFeatureOn = false

        let testSettings = ["theme": "dark", "layout": "compact"]
        mockProvider.storeSERPSettings(settings: testSettings)

        // When - Call getNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.getNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler([:], WKScriptMessage())

        // Then - Should return nil because feature flag is off
        XCTAssertNil(result, "Should return nil when feature flag is off, even if data exists")
    }

    func testGetNativeSettingsIsEmpty_ifNoDataIsPresentAndFeatureFlagIsOn() async throws {
        // Given - Feature flag is ON but no data exists
        mockProvider.mockIsSERPSettingsFeatureOn = true
        // Don't store any data

        // When - Call getNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.getNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler([:], WKScriptMessage())

        if let result = result as? EmptyPayload {
            XCTAssertTrue(result.noNativeSettings)
        } else {
            XCTFail("Result should be an EmptyPayload object")
        }
    }

    func testGetNativeSettingsReturnsPersistedSettings_whenSettingsArePersistedInNative() async throws {
        // Given - Feature flag is ON and data exists
        mockProvider.mockIsSERPSettingsFeatureOn = true

        let testSettings = ["theme": "dark", "layout": "compact"]
        mockProvider.storeSERPSettings(settings: testSettings)

        // When - Call getNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.getNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler([:], WKScriptMessage())

        // Then - Should return the stored settings
        XCTAssertNotNil(result, "Should return settings when feature is on and data exists")

        // The result is Encodable (JSONBlob wrapping Data), we need to verify the stored data
        // We can verify by checking the storage directly
        let storedResult = mockProvider.getSERPSettings()
        XCTAssertNotNil(storedResult, "Settings should be stored")

        // Verify the data was actually written to storage by reading it back
        let storedData = try mockKeyValueStore.object(forKey: SERPSettingsConstants.serpSettingsStorage) as? Data
        XCTAssertNotNil(storedData, "Data should be stored in key-value store")

        if let data = storedData {
            let decodedDict = try JSONSerialization.jsonObject(with: data) as? [String: String]
            XCTAssertEqual(decodedDict?["theme"], "dark")
            XCTAssertEqual(decodedDict?["layout"], "compact")
        }
    }

    // MARK: - updateNativeSettings message tests

    func testUpdateNativeSettingsReturnsNilAndDoesNotStoreAnything_ifFeatureFlagIsOff() async throws {
        // Given - Feature flag is OFF
        mockProvider.mockIsSERPSettingsFeatureOn = false

        // When - Call updateNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.updateNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler([:], WKScriptMessage())

        // Then - Should return nil and storeSERPSettings should have not been called
        XCTAssertNil(result, "Should return nil when feature flag is off, even if data exists")
        XCTAssertFalse(mockProvider.wasStoreSettingsCalled)
        XCTAssertNil(try mockProvider.keyValueStore?.object(forKey: SERPSettingsConstants.serpSettingsStorage))
    }

    func testUpdateNativeSettingsReturnsNilAndStoresSERPSettings_ifFeatureFlagIsOn() async throws {
        // Given - Feature flag is OFF
        mockProvider.mockIsSERPSettingsFeatureOn = true

        // When - Call updateNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.updateNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let parameters = ["theme": "dark", "layout": "compact"]
        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should return nil and storeSERPSettings should have been called
        XCTAssertNil(result, "Should return nil when feature flag is off, even if data exists")
        XCTAssertTrue(mockProvider.wasStoreSettingsCalled)

        // Then - data sent by the SERP should be stored correctly
        let storedResult = mockProvider.getSERPSettings()
        XCTAssertNotNil(storedResult, "Settings should be stored")

        // Verify the data was actually written to storage by reading it back
        let storedData = try mockKeyValueStore.object(forKey: SERPSettingsConstants.serpSettingsStorage) as? Data
        XCTAssertNotNil(storedData, "Data should be stored in key-value store")

        if let data = storedData {
            let decodedDict = try JSONSerialization.jsonObject(with: data) as? [String: String]
            XCTAssertEqual(decodedDict?["theme"], "dark")
            XCTAssertEqual(decodedDict?["layout"], "compact")
        }
    }

    // MARK: - isNativeDuckAiEnabled tests

    func testIsNativeDuckAiEnabledTests_returnTrueWhenAIIsEnabled() async throws {
        mockProvider.aiChatPreferencesStorage.isAIFeaturesEnabled = true
        // When - Call getNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.isNativeDuckAiEnabled.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler([:], WKScriptMessage())

        if let result = result as? NativeDuckAIState {
            XCTAssertTrue(result.enabled)
        } else {
            XCTFail("Result should be a boolean")
        }
    }

    func testIsNativeDuckAiEnabledTests_returnFalseWhenAIIsDisabled() async throws {
        mockProvider.aiChatPreferencesStorage.isAIFeaturesEnabled = false
        // When - Call getNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.isNativeDuckAiEnabled.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler([:], WKScriptMessage())

        if let result = result as? NativeDuckAIState {
            XCTAssertFalse(result.enabled)
        } else {
            XCTFail("Result should be a boolean")
        }
    }

    // MARK: - openNativeSettings tests

    func testOpenNativeSettings_withReturnPrivateSearch_callsCloseTabAndOpenPrivacySettings() async throws {
        // Given - Parameters with return: privateSearch
        let parameters = [SERPSettingsConstants.returnParameterKey: SERPSettingsConstants.privateSearch]

        // When - Call openNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.openNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should call the correct delegate method and return nil
        XCTAssertNil(result, "Should always return nil")
        XCTAssertEqual(mockDelegate.closeTabCallCount, 1)
        XCTAssertEqual(mockDelegate.openAIFeaturesSettingsCallCount, 0)
    }

    func testOpenNativeSettings_withReturnAIFeatures_callsCloseTabAndOpenAIFeaturesSettings() async throws {
        // Given - Parameters with return: aiFeatures
        let parameters = [SERPSettingsConstants.returnParameterKey: SERPSettingsConstants.aiFeatures]

        // When - Call openNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.openNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should call the correct delegate method and return nil
        XCTAssertNil(result, "Should always return nil")
        XCTAssertEqual(mockDelegate.closeTabCallCount, 1)
        XCTAssertEqual(mockDelegate.openAIFeaturesSettingsCallCount, 0)
    }

    func testOpenNativeSettings_withScreenAIFeatures_callsOpenAIFeaturesSettings() async throws {
        // Given - Parameters with screen: aiFeatures
        let parameters = [SERPSettingsConstants.screenParameterKey: SERPSettingsConstants.aiFeatures]

        // When - Call openNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.openNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should call the correct delegate method and return nil
        XCTAssertNil(result, "Should always return nil")
        XCTAssertEqual(mockDelegate.closeTabCallCount, 0)
        XCTAssertEqual(mockDelegate.openAIFeaturesSettingsCallCount, 1)
    }

    func testOpenNativeSettings_withInvalidParameters_doesNotCallDelegate() async throws {
        // Given - Invalid parameters
        let parameters = ["unknown": "value"]

        // When - Call openNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.openNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should not call any delegate methods and return nil
        XCTAssertNil(result, "Should always return nil")
        XCTAssertEqual(mockDelegate.closeTabCallCount, 0)
        XCTAssertEqual(mockDelegate.openAIFeaturesSettingsCallCount, 0)
    }

    func testOpenNativeSettings_withEmptyParameters_doesNotCallDelegate() async throws {
        // Given - Empty parameters
        let parameters: [String: String] = [:]

        // When - Call openNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.openNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should not call any delegate methods and return nil
        XCTAssertNil(result, "Should always return nil")
        XCTAssertEqual(mockDelegate.closeTabCallCount, 0)
        XCTAssertEqual(mockDelegate.openAIFeaturesSettingsCallCount, 0)
    }

    func testOpenNativeSettings_withNonDictionaryParameters_returnsNil() async throws {
        // Given - Non-dictionary parameters
        let parameters = "invalid"

        // When - Call openNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.openNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should return nil and not call any delegate methods
        XCTAssertNil(result, "Should return nil for invalid parameters")
        XCTAssertEqual(mockDelegate.closeTabCallCount, 0)
        XCTAssertEqual(mockDelegate.openAIFeaturesSettingsCallCount, 0)
    }

    func testOpenNativeSettings_withoutDelegate_doesNotCrash() async throws {
        // Given - No delegate set
        userScript.delegate = nil
        let parameters = [SERPSettingsConstants.returnParameterKey: SERPSettingsConstants.privateSearch]

        // When - Call openNativeSettings handler
        guard let handler = userScript.handler(forMethodNamed: SERPSettingsUserScriptMessages.openNativeSettings.rawValue) else {
            XCTFail("Handler should exist")
            return
        }

        let result = try await handler(parameters, WKScriptMessage())

        // Then - Should not crash and return nil
        XCTAssertNil(result, "Should return nil")
    }
}
