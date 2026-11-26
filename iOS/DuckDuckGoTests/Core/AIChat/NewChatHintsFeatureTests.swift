//
//  NewChatHintsFeatureTests.swift
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

import Common
import FeatureFlags_iOS
import Testing
@testable import DuckDuckGo

@Suite("New chat hints feature")
struct NewChatHintsFeatureTests {

    private enum IPhone: DevicePlatformProviding { static let isIphone = true }
    private enum IPad: DevicePlatformProviding { static let isIphone = false }

    @available(iOS 16, macOS 13, *)
    @Test("iPhone with the flag on is supported and enabled", .timeLimit(.minutes(1)))
    func iPhoneFlagOn() {
        let feature = NewChatHintsFeature(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.newChatHints]),
                                          devicePlatform: IPhone.self)
        #expect(feature.isSupported)
        #expect(feature.isEnabled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("iPhone with the flag off is supported but not enabled", .timeLimit(.minutes(1)))
    func iPhoneFlagOff() {
        let feature = NewChatHintsFeature(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []),
                                          devicePlatform: IPhone.self)
        #expect(feature.isSupported)
        #expect(!feature.isEnabled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("iPad is neither supported nor enabled, whatever the flag", .timeLimit(.minutes(1)),
          arguments: [true, false])
    func iPad(isFlagOn: Bool) {
        let feature = NewChatHintsFeature(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: isFlagOn ? [.newChatHints] : []),
                                          devicePlatform: IPad.self)
        #expect(!feature.isSupported)
        #expect(!feature.isEnabled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Enabled follows the flag as it changes while the app runs", .timeLimit(.minutes(1)))
    func flagChanges() {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let feature = NewChatHintsFeature(featureFlagger: featureFlagger, devicePlatform: IPhone.self)
        #expect(!feature.isEnabled)

        featureFlagger.enabledFeatureFlags = [.newChatHints]
        #expect(feature.isEnabled)

        featureFlagger.enabledFeatureFlags = []
        #expect(!feature.isEnabled)
        #expect(feature.isSupported)
    }
}
