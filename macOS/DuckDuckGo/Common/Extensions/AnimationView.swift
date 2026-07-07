//
//  AnimationView.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Lottie
import AppKit

extension LottieAnimationView {

    /// `.lottie` file are .zip archives, loaded async for performance. JSON animations load in place.
    convenience init?(named animationName: String, imageProvider: AnimationImageProvider? = nil) {
        if Bundle.main.containsLottieAnimation(named: animationName) {
            self.init(dotLottieName: animationName)
        } else if let animation = LottieAnimation.named(animationName, animationCache: LottieAnimationCache.shared) {
            self.init(animation: animation, imageProvider: imageProvider)
        } else {
            return nil
        }

        identifier = NSUserInterfaceItemIdentifier(rawValue: animationName)
    }
}

private extension Bundle {

    func containsLottieAnimation(named animationName: String) -> Bool {
        let lottieExtension = "lottie"
        return url(forResource: animationName, withExtension: lottieExtension) != nil
    }
}
