//
//  CASpringAnimationExtension.swift
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

extension CASpringAnimation {

    static func buildFadeInAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, toAlpha: Float = 1) -> CASpringAnimation {
        buildFadeAnimation(duration: duration, timingFunctionName: timingFunctionName, fromAlpha: 0, toAlpha: toAlpha)
    }

    static func buildFadeOutAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromAlpha: Float? = nil) -> CASpringAnimation {
        buildFadeAnimation(duration: duration, timingFunctionName: timingFunctionName, fromAlpha: fromAlpha, toAlpha: 0)
    }

    static func buildFadeAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromAlpha: Float? = nil, toAlpha: Float) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: #keyPath(CALayer.opacity))
        animation.duration = duration
        animation.fromValue = fromAlpha
        animation.toValue = toAlpha
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }

    static func buildTranslationXAnimation(duration: TimeInterval, timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut, fromValue: CGFloat, toValue: CGFloat) -> CASpringAnimation {
        let keyPath = "transform.translation.x"
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        return animation
    }
}
