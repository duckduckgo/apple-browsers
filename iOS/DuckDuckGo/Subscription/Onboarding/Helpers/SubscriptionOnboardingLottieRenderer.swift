//
//  SubscriptionOnboardingLottieRenderer.swift
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

import SwiftUI
import Lottie
import UIComponents

enum SubscriptionOnboardingLottieRenderer {
    static let shared = GraphicLottieRenderer { name, playback in
        AnyView(
            Lottie.LottieView(animation: .named(name))
                .playbackMode(playback == .playOnce
                    ? .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
                    : .paused(at: .progress(playback == .frozenAtEnd ? 1 : 0)))
        )
    }
}
