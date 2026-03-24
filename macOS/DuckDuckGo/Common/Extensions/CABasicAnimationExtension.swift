//
//  CABasicAnimationExtension.swift
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

import QuartzCore

extension CABasicAnimation {

    static func buildColorsAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromValue: [CGColor], toValue: [CGColor]) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }

    static func buildFadeInAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, toAlpha: Float = 1) -> CABasicAnimation {
        buildFadeAnimation(duration: duration, timingFunctionName: timingFunctionName, fromAlpha: 0, toAlpha: toAlpha)
    }

    static func buildFadeOutAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromAlpha: Float? = nil) -> CABasicAnimation {
        buildFadeAnimation(duration: duration, timingFunctionName: timingFunctionName, fromAlpha: fromAlpha, toAlpha: 0)
    }

    static func buildFadeAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromAlpha: Float? = nil, toAlpha: Float) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        animation.duration = duration
        animation.fromValue = fromAlpha
        animation.toValue = toAlpha
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }

    static func buildRotationAnimation(duration: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = -2 * CGFloat.pi
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    static func buildTranslationYAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromValue: CGFloat? = nil, toValue: CGFloat) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        if let fromValue {
            animation.fromValue = fromValue
        }
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }

    static func buildScaleAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromValue: CGFloat, toValue: CGFloat) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }
}
