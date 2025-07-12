//
//  Easing.swift
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

import Foundation

/// Provides easing functions for smooth animations and transitions.
///
/// Easing functions transform input values (typically time progress from 0.0 to 1.0)
/// into output values that create natural-feeling motion curves. These functions
/// are commonly used in animations to make them feel more organic and less linear.
public struct Easing {

    /// Circular easing function that starts slow, accelerates in the middle, and slows down at the end.
    ///
    /// This function creates a smooth S-curve that feels natural for most animations.
    /// The curve starts with a gentle slope, accelerates through the middle portion,
    /// and then decelerates towards the end, creating a pleasing visual effect.
    ///
    /// - Parameter x: The input value representing animation progress, typically in the range [0.0, 1.0].
    /// - Returns: The eased output value in the range [0.0, 1.0].
    ///
    /// - Note: Mathematical function taken from https://easings.net/#easeInOutCubic.
    public static func inOutCirc(_ x: Double) -> Double {
        return x < 0.5
        ? (1 - sqrt(1 - pow(2 * x, 2))) / 2
        : (sqrt(1 - pow(-2 * x + 2, 2)) + 1) / 2
    }

    private init() { }
}
