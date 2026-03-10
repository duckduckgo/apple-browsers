//
//  AddToDockVideoPlayer.swift
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

import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    struct AddToDockVideoPlayer: View {
        let url: URL
        let frameSize: CGSize
        let shouldLoopVideo: Bool

        @StateObject private var coordinator = VideoPlayerCoordinator(configuration: VideoPlayerConfiguration())

        var body: some View {
            PlayerView(coordinator: coordinator)
                .frame(width: frameSize.width, height: frameSize.height)
                .clipShape(BottomRoundedRectangle(radius: 34))
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    coordinator.pause()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    coordinator.play()
                }
                .onFirstAppear {
                    if !shouldLoopVideo {
                        coordinator.player.actionAtItemEnd = .pause // Avoid the video to disappear at the end if not looped
                    }
                    coordinator.loadAsset(url: url, shouldLoopVideo: shouldLoopVideo)
                    DispatchQueue.main.async {
                        coordinator.play()
                    }
                }
        }
    }

}
