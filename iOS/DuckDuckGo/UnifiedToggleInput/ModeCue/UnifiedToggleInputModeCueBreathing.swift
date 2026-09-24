//
//  UnifiedToggleInputModeCueBreathing.swift
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

import UIKit

/// A slow, barely-there swing of one layer property, so a steady cue feels alive without moving.
enum UnifiedToggleInputModeCueBreathing {

    private static let keyPrefix = "modeCueBreathing."

    /// Starts once; calling again while it runs is a no-op. Give each property on a layer its own
    /// period, so the swings drift in and out of phase rather than pulsing together.
    static func start(on layer: CALayer, keyPath: String, from: Any, to: Any, period: CFTimeInterval) {
        let key = keyPrefix + keyPath
        guard layer.animation(forKey: key) == nil else { return }
        let breath = CABasicAnimation(keyPath: keyPath)
        breath.fromValue = from
        breath.toValue = to
        breath.duration = period / 2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // Survives the app going to the background.
        breath.isRemovedOnCompletion = false
        layer.add(breath, forKey: key)
    }

    static func stop(on layer: CALayer, keyPath: String) {
        layer.removeAnimation(forKey: keyPrefix + keyPath)
    }
}

/// Slides a horizontal gradient's colours slowly back and forth, so the hues flow along a cue.
enum UnifiedToggleInputModeCueHueDrift {

    private static let shift: CGFloat = 0.3
    private static let period: CFTimeInterval = 6

    static func applyRestingPose(to layer: CAGradientLayer) {
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
    }

    /// Both ends move together, so the gradient keeps its length and just slides.
    static func start(on layer: CAGradientLayer) {
        UnifiedToggleInputModeCueBreathing.start(on: layer, keyPath: "startPoint",
                                                 from: NSValue(cgPoint: CGPoint(x: -shift, y: 0.5)),
                                                 to: NSValue(cgPoint: CGPoint(x: shift, y: 0.5)),
                                                 period: period)
        UnifiedToggleInputModeCueBreathing.start(on: layer, keyPath: "endPoint",
                                                 from: NSValue(cgPoint: CGPoint(x: 1 - shift, y: 0.5)),
                                                 to: NSValue(cgPoint: CGPoint(x: 1 + shift, y: 0.5)),
                                                 period: period)
    }

    static func stop(on layer: CAGradientLayer) {
        UnifiedToggleInputModeCueBreathing.stop(on: layer, keyPath: "startPoint")
        UnifiedToggleInputModeCueBreathing.stop(on: layer, keyPath: "endPoint")
    }
}
