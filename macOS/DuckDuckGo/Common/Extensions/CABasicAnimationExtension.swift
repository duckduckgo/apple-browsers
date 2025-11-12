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

    static func buildFadeInAnimation(duration: TimeInterval) -> CABasicAnimation {
        buildFadeAnimation(fromValue: 0, toValue: 1, duration: duration)
    }

    static func buildFadeOutAnimation(duration: TimeInterval) -> CABasicAnimation {
        buildFadeAnimation(fromValue: 1, toValue: 0, duration: duration)
    }

    static func buildFadeAnimation(fromValue: Float, toValue: Float, duration: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        animation.duration = duration
        animation.fromValue = fromValue
        animation.toValue = toValue
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
}
