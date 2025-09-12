//
//  SwitchBarRetentionMetricsTests.swift
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
import PersistenceTestingUtils

final class SwitchBarRetentionMetricsTests: XCTestCase {

    var mockStorage: MockKeyValueStore!
    var mockAIChatSettings: MockAIChatSettingsProvider!
    var sut: SwitchBarRetentionMetricsProviding!
    
    override func setUpWithError() throws {
        mockStorage = MockKeyValueStore()
        mockAIChatSettings = MockAIChatSettingsProvider()
        sut = SwitchBarRetentionMetrics(
            storage: mockStorage,
            pixelFiring: PixelFiringMock.self,
            aiChatSettings: mockAIChatSettings
        )
        PixelFiringMock.tearDown()
    }

    override func tearDownWithError() throws {
        mockStorage = nil
        mockAIChatSettings = nil
        sut = nil
        PixelFiringMock.tearDown()
    }

    // MARK: - First Check Tests

    // swiftlint:disable force_cast
    func testCheckDailyRetention_FirstCheck_DoesNotFirePixel() throws {
        // Given
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = true
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertTrue(mockStorage.object(forKey: "SwitchBarRetentionMetrics.lastEnabledState") as! Bool)
        XCTAssertNotNil(mockStorage.object(forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp"))
    }
    
    func testCheckDailyRetention_FirstCheckDisabled_PersistsDisabledState() throws {
        // Given
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = false
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertFalse(mockStorage.object(forKey: "SwitchBarRetentionMetrics.lastEnabledState") as! Bool)
    }

    // MARK: - 24-Hour Check Tests

    func testCheckDailyRetention_LessThan24Hours_DoesNotFirePixel() throws {
        // Given
        let currentTime = Date().timeIntervalSince1970
        let recentTime = currentTime - (23 * 60 * 60)
        mockStorage.set(true, forKey: "SwitchBarRetentionMetrics.lastEnabledState")
        mockStorage.set(recentTime, forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp")
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = true
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertNil(PixelFiringMock.lastPixelName)
    }

    // MARK: - Eligibility Check Tests

    func testCheckDailyRetention_WasDisabledLastTime_DoesNotFirePixel() throws {
        // Given
        let currentTime = Date().timeIntervalSince1970
        let dayAgo = currentTime - (25 * 60 * 60)
        mockStorage.set(false, forKey: "SwitchBarRetentionMetrics.lastEnabledState")
        mockStorage.set(dayAgo, forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp")
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = true
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertNil(PixelFiringMock.lastPixelName)
        XCTAssertTrue(mockStorage.object(forKey: "SwitchBarRetentionMetrics.lastEnabledState") as! Bool)
    }

    // MARK: - Retention Pixel Tests (Steps 4 & 5)

    func testCheckDailyRetention_RetentionCase_FiresPixelWithTrueParameter() throws {
        // Given
        let currentTime = Date().timeIntervalSince1970
        let dayAgo = currentTime - (25 * 60 * 60) // 25 hours ago
        mockStorage.set(true, forKey: "SwitchBarRetentionMetrics.lastEnabledState")
        mockStorage.set(dayAgo, forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp")
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = true
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertEqual(PixelFiringMock.lastPixelName, "m_aichat_experimental_omnibar_daily_retention")
        XCTAssertEqual(PixelFiringMock.lastParams?["still_enabled"], "true")
        XCTAssertTrue(mockStorage.object(forKey: "SwitchBarRetentionMetrics.lastEnabledState") as! Bool)
    }
    
    func testCheckDailyRetention_ChurnCase_FiresPixelWithFalseParameter() throws {
        // Given
        let currentTime = Date().timeIntervalSince1970
        let dayAgo = currentTime - (25 * 60 * 60) // 25 hours ago
        mockStorage.set(true, forKey: "SwitchBarRetentionMetrics.lastEnabledState")
        mockStorage.set(dayAgo, forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp")
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = false
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertEqual(PixelFiringMock.lastPixelName, "m_aichat_experimental_omnibar_daily_retention")
        XCTAssertEqual(PixelFiringMock.lastParams?["still_enabled"], "false")
        XCTAssertFalse(mockStorage.object(forKey: "SwitchBarRetentionMetrics.lastEnabledState") as! Bool)
    }

    // MARK: - Edge Case Tests

    func testCheckDailyRetention_Exactly24Hours_FiresPixel() throws {
        // Given
        let currentTime = Date().timeIntervalSince1970
        let exactlyDayAgo = currentTime - (24 * 60 * 60) // Exactly 24 hours
        mockStorage.set(true, forKey: "SwitchBarRetentionMetrics.lastEnabledState")
        mockStorage.set(exactlyDayAgo, forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp")
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = true
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertEqual(PixelFiringMock.lastPixelName, "m_aichat_experimental_omnibar_daily_retention")
    }
    
    func testCheckDailyRetention_MultiDayGap_FiresPixel() throws {
        // Given
        let currentTime = Date().timeIntervalSince1970
        let threeDaysAgo = currentTime - (72 * 60 * 60) // 72 hours ago
        mockStorage.set(true, forKey: "SwitchBarRetentionMetrics.lastEnabledState")
        mockStorage.set(threeDaysAgo, forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp")
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = true
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        XCTAssertEqual(PixelFiringMock.lastPixelName, "m_aichat_experimental_omnibar_daily_retention")
        XCTAssertEqual(PixelFiringMock.lastParams?["still_enabled"], "true")
    }

    // MARK: - State Persistence Tests

    func testCheckDailyRetention_AlwaysUpdatesTimestamp() throws {
        // Given
        let currentTime = Date().timeIntervalSince1970
        let dayAgo = currentTime - (25 * 60 * 60)
        mockStorage.set(true, forKey: "SwitchBarRetentionMetrics.lastEnabledState")
        mockStorage.set(dayAgo, forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp")
        mockAIChatSettings.isAIChatSearchInputUserSettingsEnabled = false
        
        // When
        sut.checkDailyAndSendPixelIfApplicable()
        
        // Then
        let updatedTimestamp = mockStorage.object(forKey: "SwitchBarRetentionMetrics.lastCheckTimestamp") as! Double
        XCTAssertGreaterThan(updatedTimestamp, currentTime - 1) // Within 1 second
    }
    // swiftlint:enable force_cast
}
