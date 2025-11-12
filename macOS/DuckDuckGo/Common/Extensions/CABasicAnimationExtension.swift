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

    static func buildFadeInAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut) -> CABasicAnimation {
        buildFadeAnimation(duration: duration, timingFunctionName: timingFunctionName, fromValue: 0, toValue: 1)
    }

    static func buildFadeOutAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut) -> CABasicAnimation {
        buildFadeAnimation(duration: duration, timingFunctionName: timingFunctionName, fromValue: 1, toValue: 0)
    }

    static func buildFadeAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName, fromValue: Float, toValue: Float) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        animation.duration = duration
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }

    static func buildRotationAnimation(duration: TimeInterval) -> CABasicAnimation {
        let keyPath = "transform.rotation.z"
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = 0
        animation.toValue = -2 * CGFloat.pi
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    static func buildTranslationXAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromValue: CGFloat, toValue: CGFloat) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }
}
