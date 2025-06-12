//
//  VideoPlayerView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import AVFoundation

// AVKit provides a SwiftUI view called VideoPlayer view to render AVPlayer.
// The issue is that is not possible to change the background/foreground colour of the view so the default colour is black.
// Using UIKit -> AVPlayerLayer solves the problem.
struct PlayerView: UIViewRepresentable {
    private let coordinator: VideoPlayerCoordinator

    init(coordinator: VideoPlayerCoordinator) {
        self.coordinator = coordinator
    }

    func makeCoordinator() -> VideoPlayerCoordinator {
        coordinator
    }

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView(player: coordinator.player)
        coordinator.setupPictureInPicture(playerLayer: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<PlayerView>) {
    }
}

private final class PlayerUIView: UIView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        playerLayer.player = player
        super.init(frame: .zero)
        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Preview

struct PlayerView_Previews: PreviewProvider {

    @MainActor
    struct PlayerPreview: View {
        static let videoURL = Bundle.main.url(forResource: "add-to-dock-demo", withExtension: "mp4")!
        @State var model = VideoPlayerCoordinator(url: Self.videoURL, configuration: .init(loopVideo: true))

        var body: some View {
            PlayerView(
                coordinator: model
            )
            .onAppear(perform: {
                model.play()
            })
        }
    }

    static var previews: some View {
        PlayerPreview()
            .preferredColorScheme(.light)
   }
}
