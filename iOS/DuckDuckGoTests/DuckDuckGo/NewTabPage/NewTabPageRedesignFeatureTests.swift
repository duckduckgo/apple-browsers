//
//  NewTabPageRedesignFeatureTests.swift
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

import FeatureFlags_iOS
import Testing
@testable import DuckDuckGo

struct NewTabPageRedesignFeatureTests {

    private enum IphonePlatform: DevicePlatformProviding {
        static let isIphone = true
    }

    private enum IPadPlatform: DevicePlatformProviding {
        static let isIphone = false
    }

    private func makeFeature(enabledFlags: [FeatureFlag], isIphone: Bool = true) -> NewTabPageRedesignFeature {
        NewTabPageRedesignFeature(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFlags),
                                  devicePlatform: isIphone ? IphonePlatform.self : IPadPlatform.self)
    }

    @available(iOS 16, *)
    @Test("Redesign is available on iPhone when its flag is on", .timeLimit(.minutes(1)))
    func availableOnIphoneWhenFlagOn() {
        #expect(makeFeature(enabledFlags: [.newTabPageRedesign]).isAvailable)
    }

    @available(iOS 16, *)
    @Test("Redesign is unavailable when its flag is off", .timeLimit(.minutes(1)))
    func unavailableWhenFlagOff() {
        #expect(!makeFeature(enabledFlags: []).isAvailable)
    }

    @available(iOS 16, *)
    @Test("Redesign is unavailable on iPad even with its flag on", .timeLimit(.minutes(1)))
    func unavailableOnIPad() {
        #expect(!makeFeature(enabledFlags: [.newTabPageRedesign], isIphone: false).isAvailable)
    }
}
