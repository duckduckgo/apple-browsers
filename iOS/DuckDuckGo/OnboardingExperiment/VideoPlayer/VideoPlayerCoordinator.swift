//
//  VideoPlayerCoordinator.swift
//  DuckDuckGo
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

import AVKit
import Combine

struct VideoPlayerConfiguration {
    /// A Boolean value that indicates whether the video should loop. Default value is `false`
    var loopVideo: Bool = false
    /// A Boolean value that indicates whether the layer prevents the system from sleeping during video playback. Default value is `false`
    ///
    /// Setting this property to false doesn’t force the display to sleep; it only stops preventing display sleep. Other apps or frameworks within your app may still be preventing display sleep for various reasons.
    var preventsDisplaySleepDuringVideoPlayback: Bool = false
    
    /// A Boolean value that indicates whether the player allows switching to external playback mode (E.g. AirPlay). Default value is `false`
    var allowsExternalPlayback: Bool = false
    
    /// A Boolean value that indicates whether Picture in Picture starts automatically when the controller embeds its content inline and the app transitions to the background. Default value is `false`
    var allowsPictureInPicturePlayback: Bool = false

    /// A Boolean value that determines whether the controller allows the user to skip media content.
    ///
    /// This is used for showing/hiding the skip controls on the Picture in Picture window.
    var requiresLinearPlayback: Bool = false
}

final class VideoPlayerCoordinator: ObservableObject {
    @Published private(set) var player: AVPlayer
    @Published private(set) var isPictureInPictureActive: Bool = false

    @Published private var pictureInPictureController: PictureInPictureControlling
    private var pictureInPictureActiveCancellable: AnyCancellable?

    let url: URL
    private let audioSessionManager: AudioSessionManaging
    private var playerLooper: AVPlayerLooper?

    var isLoopingVideo: Bool {
        playerLooper != nil
    }

    init(
        url: URL,
        configuration: VideoPlayerConfiguration,
        player: AVQueuePlayer,
        pictureInPictureController: PictureInPictureControlling,
        audioSessionManager: AudioSessionManaging
    ) {
        self.url = url
        self.player = player
        self.pictureInPictureController = pictureInPictureController
        self.audioSessionManager = audioSessionManager
        bind()
        configureVideoPlayer(configuration: configuration)
        loadAsset(in: player, shouldLoopVideo: configuration.loopVideo)
    }

    convenience init(url: URL, configuration: VideoPlayerConfiguration) {
        self.init(
            url: url,
            configuration: configuration,
            player: AVQueuePlayer(),
            pictureInPictureController: PictureInPictureController(
                configuration: PictureInPictureConfiguration(
                    canStartPictureInPictureAutomaticallyFromInline: configuration.allowsPictureInPicturePlayback,
                    requiresLinearPlayback: configuration.requiresLinearPlayback
                )
            ),
            audioSessionManager: AudioSessionManager()
        )
    }

    func play() {
        Logger.videoPlayer.debug("[Video Player] - Play")
        player.play()
    }

    func pause() {
        Logger.videoPlayer.debug("[Video Player] - Pause")
        player.pause()
    }

    func setupPictureInPicture(playerLayer: AVPlayerLayer) {
        Logger.videoPlayer.debug("[Video Player] - Setup Picture in Picture")
        pictureInPictureController.setupPictureInPicture(playerLayer: playerLayer)
    }

    func stopPictureInPicture() {
        Logger.videoPlayer.debug("[Video Player] - Stop Picture In Picture")
        pictureInPictureController.stopPictureInPicture()
    }

    deinit {
        Logger.videoPlayer.debug("[Video Player] - Video Coordinator deinitialized")
        audioSessionManager.setPlaybackSessionInactive()
    }
}

// MARK: - Private

private extension VideoPlayerCoordinator {

    func bind() {
        pictureInPictureActiveCancellable = pictureInPictureController
            .pictureInPictureEventPublisher
            .handleEvents(receiveOutput: { event in
                Logger.videoPlayer.debug("[Video Player] - Received Picture In Picture Event: \(event.debugDescription)")
            })
            .compactMap { event in
                switch event {
                case .willStartPictureInPicture:
                    nil
                case .didStartPictureInPicture:
                    true
                case .willStopPictureInPicture:
                    nil
                case.didStopPictureInPicture, .failedToStartPictureInPicture:
                    false
                }
            }
            .assign(to: \.isPictureInPictureActive, onWeaklyHeld: self)
    }

    func configureVideoPlayer(configuration: VideoPlayerConfiguration) {
        // Let the application goes to sleep if needed when the video is playing. Default value is false as we're not playing a movie.
        player.preventsDisplaySleepDuringVideoPlayback = configuration.preventsDisplaySleepDuringVideoPlayback
        // Disable playback video on external displays.
        player.allowsExternalPlayback = configuration.allowsExternalPlayback
        // If the video can continue playing in the background in a PiP window, activate the audio session.
        if configuration.allowsPictureInPicturePlayback {
            audioSessionManager.setPlaybackSessionActive()
        }
    }

    func loadAsset(in player: AVQueuePlayer, shouldLoopVideo: Bool) {
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        if shouldLoopVideo {
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        }
    }

}
