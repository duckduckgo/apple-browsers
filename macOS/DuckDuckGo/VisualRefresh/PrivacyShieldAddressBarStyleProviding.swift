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

import AppKit
import DesignResourcesKitIcons

protocol PrivacyShieldAddressBarStyleProviding {
    var icon: NSImage { get }
    var iconWithDot: NSImage { get }

    /// Animations
    var hoverAnimation: String { get }
    var hoverAnimationWithDot: String { get }

    var animationForShield: String { get }
    var animationForShieldWithDot: String { get }
}

final class LegacyPrivacyShieldAddressBarStyleProvider: PrivacyShieldAddressBarStyleProviding {
    let icon: NSImage = DesignSystemImages.Color.Size16.shieldCheck
    let iconWithDot: NSImage = DesignSystemImages.Color.Size16.shieldNeutralAlert

    let hoverAnimation: String = "shield-green-hover"
    let hoverAnimationWithDot: String = "shield-gray-dot-hover"
    let animationForShield: String = "shield.new"
    let animationForShieldWithDot: String = "shield-dot-new"
}

final class LatestPrivacyShieldAddressBarStyleProvider: PrivacyShieldAddressBarStyleProviding {
    let icon: NSImage = DesignSystemImages.Color.Size16.shieldCheck
    let iconWithDot: NSImage = DesignSystemImages.Color.Size16.shieldNeutralAlert

    let hoverAnimation: String = "Shield-Color-24-Hover"
    let hoverAnimationWithDot: String = "Shield-Off-Gray"
    let animationForShield: String = "Shield-Color-24"
    let animationForShieldWithDot: String = "Shield-Off-Gray"
}
