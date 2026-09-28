//
//  NetworkProtectionStatusViewTintSpecTests.swift
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
import Lottie
@testable import DuckDuckGo

/// Guards the strict-routing tint against silent no-ops: `setValueProvider` does nothing when a
/// keypath doesn't resolve, so if a VPN header animation is re-exported with different layer
/// names the tint would quietly stop applying. This asserts every keypath in each `TintSpec`
/// exists in the corresponding bundled animation.
final class NetworkProtectionStatusViewTintSpecTests: XCTestCase {

    private typealias TintSpec = NetworkProtectionStatusView.TintSpec

    func testTintSpecKeypathsExistInBundledAnimations() throws {
        let animations: [(name: String, spec: TintSpec)] = [
            ("vpn-animation", .rebranded),
            ("vpn-light-mode-legacy", .legacy),
            ("vpn-dark-mode-legacy", .legacy)
        ]

        for (name, spec) in animations {
            let animation = try XCTUnwrap(LottieAnimation.named(name), "Bundled animation \(name) not found")
            // The main-thread rendering engine is required: it builds the full layer hierarchy
            // synchronously, so `allHierarchyKeypaths()` reports leaf properties like `Color`.
            let animationView = LottieAnimationView(animation: animation,
                                                    configuration: LottieConfiguration(renderingEngine: .mainThread))
            let availableKeypaths = Set(animationView.allHierarchyKeypaths())

            var expectedKeypaths = [spec.badgeKeypath] + spec.lockKeypaths
            expectedKeypaths += spec.accentLineKeypaths.flatMap { [$0.fill, $0.stroke] }

            for keypath in expectedKeypaths {
                XCTAssertTrue(availableKeypaths.contains(keypath),
                              "\(name) is missing keypath \(keypath); the strict-routing tint would silently no-op")
            }
        }
    }
}
