//
//  PrivacyShieldAddressBarStyleProviding.swift
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

protocol PrivacyShieldAddressBarStyleProviding {
    var icon: NSImage { get }
    var iconWithDot: NSImage { get }

    /// Animations
    func hoverAnimation(forLightMode: Bool) -> String
    func hoverAnimationWithDot(forLightMode: Bool) -> String

    func animationForShield(forLightMode: Bool) -> String
    func animationForShieldWithDot(forLightMode: Bool) -> String
}

final class LegacyPrivacyShieldAddressBarStyleProvider: PrivacyShieldAddressBarStyleProviding {
    let icon: NSImage = .shield
    let iconWithDot: NSImage = .shieldDot

    func hoverAnimation(forLightMode: Bool) -> String {
        forLightMode ? "shield-mouse-over" : "dark-shield-mouse-over"
    }

    func hoverAnimationWithDot(forLightMode: Bool) -> String {
        forLightMode ? "shield-dot-mouse-over" : "dark-shield-dot-mouse-over"
    }

    func animationForShield(forLightMode: Bool) -> String {
        forLightMode ? "shield" : "dark-shield"
    }

    func animationForShieldWithDot(forLightMode: Bool) -> String {
        forLightMode ? "shield-dot" : "dark-shield-dot"
    }
}

final class NewPrivacyShieldAddressBarStyleProvider: PrivacyShieldAddressBarStyleProviding {
    let icon: NSImage = .privacyShieldNew
    let iconWithDot: NSImage = .privacyShieldDotNew

    func hoverAnimation(forLightMode: Bool) -> String {
        "shield-green-hover" /// We use the same animation for both dark and light
    }

    func hoverAnimationWithDot(forLightMode: Bool) -> String {
        "shield-gray-dot-hover" /// We use the same animation for both dark and light
    }

    func animationForShield(forLightMode: Bool) -> String {
        forLightMode ? "shield-new" : "dark-shield-new"
    }

    func animationForShieldWithDot(forLightMode: Bool) -> String {
        forLightMode ? "shield-dot-new" : "dark-shield-dot-new"
    }
}
