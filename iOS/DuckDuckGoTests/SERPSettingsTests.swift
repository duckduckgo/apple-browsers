//
//  SERPSettingsTests.swift
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
import Foundation
import BrowserServicesKit
import AIChat
import Core
import Persistence
import PersistenceTestingUtils

@testable import DuckDuckGo

final class SERPSettingsTests: XCTestCase {
    private var mockKeyValueStore: MockKeyValueStore!
    private var mockAIChatSettings: MockAIChatSettingsProvider!
    private var mockNotificationCenter: NotificationCenter!
    private var serpSettings: SERPSettings!
    
    private let allowFollowUpQuestionsKey = "serp.settings.allowFollowUpQuestions"
    
    override func setUp() {
        super.setUp()
        mockKeyValueStore = MockKeyValueStore()
        mockAIChatSettings = MockAIChatSettingsProvider()
        mockNotificationCenter = NotificationCenter()
        
        serpSettings = SERPSettings(keyValueStore: mockKeyValueStore,
                                    aiChatSettings: mockAIChatSettings,
                                    notificationCenter: mockNotificationCenter)
    }
    
    override func tearDown() {
        mockKeyValueStore = nil
        mockAIChatSettings = nil
        mockNotificationCenter = nil
        serpSettings = nil
        super.tearDown()
    }
    
    func test_isAIChatEnabled_WhenAIChatEnabled_ReturnsTrue() {
        // GIVEN
        mockAIChatSettings.isAIChatEnabled = true
        
        // WHEN & THEN
        XCTAssertTrue(serpSettings.isAIChatEnabled)
    }
    
    func test_isDuckAIEnabled_WhenAIChatDisabled_ReturnsFalse() {
        // GIVEN
        mockAIChatSettings.isAIChatEnabled = false
        
        // WHEN & THEN
        XCTAssertFalse(serpSettings.isAIChatEnabled)
    }
    
    func test_isAllowFollowUpQuestionsEnabled_WhenNotSet_ReturnsNil() {
        // GIVEN
        // No value set in the key value store
        
        // WHEN & THEN
        XCTAssertNil(serpSettings.isAllowFollowUpQuestionsEnabled)
    }
    
    func test_isAllowFollowUpQuestionsEnabled_WhenSetToTrue_ReturnsTrue() throws {
        // GIVEN
        mockKeyValueStore.set(true, forKey: allowFollowUpQuestionsKey)
        
        // WHEN
        let result = try XCTUnwrap(serpSettings.isAllowFollowUpQuestionsEnabled)
        
        // THEN
        XCTAssertTrue(result)
    }
    
    func test_isAllowFollowUpQuestionsEnabled_WhenSetToFalse_ReturnsFalse() throws {
        // GIVEN
        mockKeyValueStore.set(false, forKey: allowFollowUpQuestionsKey)
        
        // WHEN
        let result = try XCTUnwrap(serpSettings.isAllowFollowUpQuestionsEnabled)
        
        // THEN
        XCTAssertFalse(result)
    }
    
    func test_didMigrate_WhenFollowUpQuestionsNotSet_ReturnsFalse() {
        // GIVEN
        // No value set in the key value store
        
        // WHEN & THEN
        XCTAssertFalse(serpSettings.didMigrate)
    }
    
    func test_didMigrate_WhenFollowUpQuestionsSet_ReturnsTrue() {
        // GIVEN
        mockKeyValueStore.set(true, forKey: allowFollowUpQuestionsKey)
        
        // WHEN & THEN
        XCTAssertTrue(serpSettings.didMigrate)
    }
    
    // MARK: - Method Tests
    
    func test_enableAllowFollowUpQuestions_WhenEnableTrue_StoresValueAndPostsNotification() {
        // GIVEN
        var notificationPosted = false
        let expectation = XCTestExpectation(description: "Notification posted")
        
        let observer = mockNotificationCenter.addObserver(forName: .serpSettingsChanged, object: nil, queue: nil) { _ in
            notificationPosted = true
            expectation.fulfill()
        }
        
        // WHEN
        serpSettings.enableAllowFollowUpQuestions(enable: true)
        
        // THEN
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationPosted)
        XCTAssertTrue(mockKeyValueStore.object(forKey: allowFollowUpQuestionsKey) as? Bool == true)
        
        mockNotificationCenter.removeObserver(observer)
    }
    
    func test_enableAllowFollowUpQuestions_WhenEnableFalse_StoresValueAndPostsNotification() {
        // GIVEN
        var notificationPosted = false
        let expectation = XCTestExpectation(description: "Notification posted")
        
        let observer = mockNotificationCenter.addObserver(forName: .serpSettingsChanged, object: nil, queue: nil) { _ in
            notificationPosted = true
            expectation.fulfill()
        }
        
        // WHEN
        serpSettings.enableAllowFollowUpQuestions(enable: false)
        
        // THEN
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationPosted)
        XCTAssertTrue(mockKeyValueStore.object(forKey: allowFollowUpQuestionsKey) as? Bool == false)
        
        mockNotificationCenter.removeObserver(observer)
    }
    
    func test_migrateAllowFollowUpQuestions_WhenEnableTrue_StoresValueWithoutNotification() {
        // GIVEN
        var notificationPosted = false
        let expectation = XCTestExpectation(description: "No notification posted")
        expectation.isInverted = true
        
        let observer = mockNotificationCenter.addObserver(forName: .serpSettingsChanged, object: nil, queue: nil) { _ in
            notificationPosted = true
            expectation.fulfill()
        }
        
        // WHEN
        serpSettings.migrateAllowFollowUpQuestions(enable: true)
        
        // THEN
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(notificationPosted)
        XCTAssertTrue(mockKeyValueStore.object(forKey: allowFollowUpQuestionsKey) as? Bool == true)
        
        mockNotificationCenter.removeObserver(observer)
    }
    
    func test_migrateAllowFollowUpQuestions_WhenEnableFalse_StoresValueWithoutNotification() {
        // GIVEN
        var notificationPosted = false
        let expectation = XCTestExpectation(description: "No notification posted")
        expectation.isInverted = true
        
        let observer = mockNotificationCenter.addObserver(forName: .serpSettingsChanged, object: nil, queue: nil) { _ in
            notificationPosted = true
            expectation.fulfill()
        }
        
        // WHEN
        serpSettings.migrateAllowFollowUpQuestions(enable: false)
        
        // THEN
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(notificationPosted)
        XCTAssertTrue(mockKeyValueStore.object(forKey: allowFollowUpQuestionsKey) as? Bool == false)
        
        mockNotificationCenter.removeObserver(observer)
    }
    
    // MARK: - Integration Tests
    
    func test_enableFollowUpQuestions_ThenCheckDidMigrate_ReturnsTrue() {
        // GIVEN
        XCTAssertFalse(serpSettings.didMigrate)
        
        // WHEN
        serpSettings.enableAllowFollowUpQuestions(enable: true)
        
        // THEN
        XCTAssertTrue(serpSettings.didMigrate)
        XCTAssertTrue(serpSettings.isAllowFollowUpQuestionsEnabled == true)
    }
    
    func test_migrateFollowUpQuestions_ThenCheckDidMigrate_ReturnsTrue() {
        // GIVEN
        XCTAssertFalse(serpSettings.didMigrate)
        
        // WHEN
        serpSettings.migrateAllowFollowUpQuestions(enable: false)
        
        // THEN
        XCTAssertTrue(serpSettings.didMigrate)
        XCTAssertTrue(serpSettings.isAllowFollowUpQuestionsEnabled == false)
    }
}
