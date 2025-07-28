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
import CombineSchedulers

struct VideoPlayerConfiguration {
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
    @Published private(set) var playerItemStatus: AVPlayerItem.Status = .unknown
    @Published private(set) var player: AVQueuePlayer
    @Published private(set) var isPictureInPictureActive: Bool = false

    @Published private var pictureInPictureController: PictureInPictureControlling

    private var pictureInPictureActiveCancellable: AnyCancellable?
    private var playerItemStatusCancellable: AnyCancellable?

    private(set) var url: URL?
    private let audioSessionManager: AudioSessionManaging
    private var playerLooper: AVPlayerLooper?

    private let scheduler: AnySchedulerOf<DispatchQueue>

    var isLoopingVideo: Bool {
        playerLooper != nil
    }

    init(
        configuration: VideoPlayerConfiguration,
        player: AVQueuePlayer,
        pictureInPictureController: PictureInPictureControlling,
        audioSessionManager: AudioSessionManaging,
        scheduler: AnySchedulerOf<DispatchQueue> = DispatchQueue.main.eraseToAnyScheduler()
    ) {
        self.player = player
        self.pictureInPictureController = pictureInPictureController
        self.audioSessionManager = audioSessionManager
        self.scheduler = scheduler
        bind()
        configureVideoPlayer(configuration: configuration)
    }

    convenience init(configuration: VideoPlayerConfiguration) {
        self.init(
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

    @discardableResult
    func loadAsset(url: URL, shouldLoopVideo: Bool = false) -> Task<Void, Never> {
        Logger.videoPlayer.debug("[Video Player] - Loading Asset with URL: \(url). Looping video: \(shouldLoopVideo)")
        self.url = url

        return Task(priority: .userInitiated) { @MainActor in
            do {
                try await performLoadAsset(url: url, shouldLoopVideo: shouldLoopVideo)
            } catch {
                Logger.videoPlayer.error("Video Is Not Playable. Error: \(error)")
                playerItemStatus = .failed
            }
        }
    }

    func play() {
        Logger.videoPlayer.debug("[Video Player] - Play")
        player.play()
    }

    func pause() {
        Logger.videoPlayer.debug("[Video Player] - Pause")
        player.pause()
    }

    func stop() {
        playerLooper?.disableLooping()
        player.removeAllItems()
        playerItemStatus = .unknown
    }

    func isPictureInPictureSupported() -> Bool {
        pictureInPictureController.isPictureInPictureSupported()
    }

    func setupPictureInPicture(playerLayer: AVPlayerLayer) {
        Logger.videoPlayer.debug("[Video Player] - Setup Picture in Picture")
        pictureInPictureController.setupPictureInPicture(playerLayer: playerLayer)
    }

    func stopPictureInPicture() {
        guard isPictureInPictureActive else { return }
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
            .receive(on: scheduler)
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

    func performLoadAsset(url: URL, shouldLoopVideo: Bool) async throws  {
        let asset = AVURLAsset(url: url)

        guard try await asset.load(.isPlayable) else {
            Logger.videoPlayer.error("Video Is Not Playable.")
            await MainActor.run {
                playerItemStatus = .failed
            }
            return
        }

        await MainActor.run {
            let playerItem = AVPlayerItem(asset: asset)
            observePlayerItemStatus()

            if shouldLoopVideo {
                playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            } else {
                player.replaceCurrentItem(with: playerItem)
            }
        }
    }

    func observePlayerItemStatus() {
        // Observe Player Item Status
        playerItemStatusCancellable = player.publisher(for: \.currentItem?.status, options: [.initial, .new])
            .receive(on: scheduler)
            .compactMap { $0 }
            .handleEvents(receiveOutput: { status in
                switch status {
                case .readyToPlay:
                    Logger.videoPlayer.debug("[Video Player] - Player Item is ready to play.")
                case .failed:
                    Logger.videoPlayer.debug("[Video Player] - Player Item playback failed.")
                case .unknown:
                    Logger.videoPlayer.debug("[Video Player] - Player Item Unknown status.")
                @unknown default:
                    Logger.videoPlayer.debug("[Video Player] - Player Item Unknown status.")
                }
            })
            .assign(to: \.playerItemStatus, onWeaklyHeld: self)
    }

}
