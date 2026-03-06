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

import AVFoundation
import Onboarding
import SwiftUI

extension OnboardingRebranding.OnboardingView {

    struct AddToDockVideoPlayer: View {
        let url: URL
        let frameSize: CGSize

        @StateObject private var coordinator = VideoPlayerCoordinator(configuration: VideoPlayerConfiguration())
        @State private var aspectRatio: CGFloat?

        var body: some View {
            PlayerView(coordinator: coordinator)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    coordinator.pause()
                }
                .frame(width: frameSize.width, height: frameSize.height)
//                .clipShape(BottomRoundedRectangle(radius: 34))
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    coordinator.play()
                }
                .onFirstAppear {
                    coordinator.loadAsset(url: url, shouldLoopVideo: true)
                    DispatchQueue.main.async {
                        coordinator.play()
                    }
                }
                .task {
                    await loadVideoAspectRatio()
                }
        }

        @MainActor
        private func loadVideoAspectRatio() async {
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let naturalSize = try? await track.load(.naturalSize),
                  naturalSize.height > 0 else { return }
            aspectRatio = naturalSize.width / naturalSize.height
        }
    }

}
