//
//  DuckPlayerSettingsTests.swift
//  DuckDuckGo
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
@testable import Core
@testable import DuckDuckGo
import BrowserServicesKit
import Combine
import UIKit

// Mock UIDevice to control userInterfaceIdiom
class MockUIDevice: UIDevice {
    static var mockUserInterfaceIdiom: UIUserInterfaceIdiom = .phone
    
    override var userInterfaceIdiom: UIUserInterfaceIdiom {
        return MockUIDevice.mockUserInterfaceIdiom
    }
}

// Swizzle UIDevice.current to return our mock
extension UIDevice {
    static let originalDevice = UIDevice.current
    static var mockDevice = MockUIDevice()
    
    @objc static var swizzledCurrent: UIDevice {
        return mockDevice
    }
    
    static func swizzleCurrent() {
        let originalSelector = #selector(getter: UIDevice.current)
        let swizzledSelector = #selector(getter: UIDevice.swizzledCurrent)
        
        let originalMethod = class_getClassMethod(UIDevice.self, originalSelector)!
        let swizzledMethod = class_getClassMethod(UIDevice.self, swizzledSelector)!
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    static func unswizzleCurrent() {
        let originalSelector = #selector(getter: UIDevice.current)
        let swizzledSelector = #selector(getter: UIDevice.swizzledCurrent)
        
        let originalMethod = class_getClassMethod(UIDevice.self, originalSelector)!
        let swizzledMethod = class_getClassMethod(UIDevice.self, swizzledSelector)!
        
        method_exchangeImplementations(swizzledMethod, originalMethod)
    }
}

class DuckPlayerSettingsTests: XCTestCase {

    private var mockAppSettings: AppSettingsMock!
    private var mockPrivacyConfig: PrivacyConfigurationManagerMock!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var settings: DuckPlayerSettingsDefault!
    private var internalUserDecider: MockInternalUserDecider!

    override func setUp() {
        super.setUp()
        // Swizzle UIDevice.current to use our mock
        UIDevice.swizzleCurrent()
        MockUIDevice.mockUserInterfaceIdiom = .phone
        
        mockAppSettings = AppSettingsMock()
        mockPrivacyConfig = PrivacyConfigurationManagerMock()
        mockFeatureFlagger = MockFeatureFlagger()
        internalUserDecider = MockInternalUserDecider()
        settings = DuckPlayerSettingsDefault(appSettings: mockAppSettings,
                                           privacyConfigManager: mockPrivacyConfig,
                                           featureFlagger: mockFeatureFlagger)
    }

    override func tearDown() {
        mockAppSettings = nil
        mockFeatureFlagger = nil
        settings = nil
        
        // Restore the original UIDevice.current
        UIDevice.unswizzleCurrent()
        super.tearDown()
    }
    
    func testNativeUISettingsDisabledWhenFeatureFlagOff() {
        // Setup: Device is phone, feature flag disabled
        MockUIDevice.mockUserInterfaceIdiom = .phone
        mockFeatureFlagger.enabledFeatureFlags = [.duckPlayer] // DuckPlayerNativeUI not enabled
        // Use the correct internal user decider mock and set to false
        let mockInternalUserDecider = MockDuckPlayerInternalUserDecider()
        mockInternalUserDecider.mockIsInternalUser = false
        mockFeatureFlagger.internalUserDecider = mockInternalUserDecider
        
        // Configure app settings with defaults
        mockAppSettings.duckPlayerNativeUI = true
        mockAppSettings.duckPlayerNativeUISERPEnabled = true
        mockAppSettings.duckPlayerAutoplay = true
        mockAppSettings.duckPlayerNativeYoutubeMode = .ask
        
        // Re-initialize settings with the updated feature flagger and internal user decider
        settings = DuckPlayerSettingsDefault(appSettings: mockAppSettings,
                                           privacyConfigManager: mockPrivacyConfig,
                                           featureFlagger: mockFeatureFlagger,
                                           internalUserDecider: mockInternalUserDecider)
        
        // Test that nativeUI is disabled when feature flag is off
        XCTAssertFalse(settings.nativeUI, "nativeUI should be false when feature flag is disabled")
        
        // Test that native UI SERP is disabled when feature flag is off
        XCTAssertFalse(settings.nativeUISERPEnabled, "nativeUISERPEnabled should be false when feature flag is disabled")
        
        // Test that autoplay is disabled when feature flag is off
        XCTAssertFalse(settings.autoplay, "autoplay should be false when feature flag is disabled")
        
        // Test that Youtube mode is set to .never when feature flag is off
        XCTAssertEqual(settings.nativeUIYoutubeMode, .never, "nativeUIYoutubeMode should be .never when feature flag is disabled")
        
        // Now enable the feature flag and verify settings are available
        mockFeatureFlagger.enabledFeatureFlags = [.duckPlayer, .duckPlayerNativeUI]
        
        // Re-initialize settings with updated feature flags
        settings = DuckPlayerSettingsDefault(appSettings: mockAppSettings,
                                           privacyConfigManager: mockPrivacyConfig,
                                           featureFlagger: mockFeatureFlagger,
                                           internalUserDecider: mockInternalUserDecider)
        
        // Test that nativeUI is now enabled
        XCTAssertTrue(settings.nativeUI, "nativeUI should be true when feature flag is enabled")
        
        // Test that native UI SERP is now enabled
        XCTAssertTrue(settings.nativeUISERPEnabled, "nativeUISERPEnabled should be true when feature flag is enabled")
        
        // Test that autoplay is now enabled
        XCTAssertTrue(settings.autoplay, "autoplay should be true when feature flag is enabled")
        
        // Test that Youtube mode is properly set to ask (default)
        XCTAssertEqual(settings.nativeUIYoutubeMode, .ask, "nativeUIYoutubeMode should be .ask when feature flag is enabled")
    }
}
