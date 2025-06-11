//
//  PictureInPictureController.swift
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

struct PictureInPictureConfiguration {
    /// A Boolean value that indicates whether Picture in Picture starts automatically when the controller embeds its content inline and the app transitions to the background. Default value is false.
    var canStartPictureInPictureAutomaticallyFromInline: Bool = false
    /// A Boolean value that determines whether the controller allows the user to skip media content. Default value is true meaning that the skip playback controls won't be shown.
    var requiresLinearPlayback: Bool = true
}

final class PictureInPictureController: NSObject, ObservableObject {
    @Published private(set) var isPictureInPictureActive: Bool = false

    private let configuration: PictureInPictureConfiguration
    private let audioSessionManager: AudioSessionManaging
    private var controller: AVPictureInPictureController?
    private var pictureInPictureCancellable: AnyCancellable?

    init(
        configuration: PictureInPictureConfiguration = .init(),
        audioSessionManager: AudioSessionManaging = AudioSessionManager()
    ) {
        self.configuration = configuration
        self.audioSessionManager = audioSessionManager
        audioSessionManager.setPlaybackSessionActive()
        super.init()
    }

    deinit {
        audioSessionManager.setPlaybackSessionInactive()
    }

}

// MARK: - Public

extension PictureInPictureController {

    func setupPictureInPicture(playerLayer: AVPlayerLayer) {
        guard
            AVPictureInPictureController.isPictureInPictureSupported(),
            let controller = AVPictureInPictureController(playerLayer: playerLayer)
        else {
            return
        }
        Logger.videoPlayer.debug("PictureInPictureController initialised")

        controller.canStartPictureInPictureAutomaticallyFromInline = configuration.canStartPictureInPictureAutomaticallyFromInline
        controller.requiresLinearPlayback = configuration.requiresLinearPlayback
        controller.delegate = self
        self.controller = controller
    }

    func startPictureInPicture() {
        controller?.startPictureInPicture()
    }

    func stopPictureInPicture() {
        controller?.stopPictureInPicture()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PictureInPictureController: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.videoPlayer.debug("Picture in Picture Started")
        isPictureInPictureActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.videoPlayer.debug("Picture in Picture Stopped")
        isPictureInPictureActive = false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        Logger.videoPlayer.debug("Picture in Picture Failed: \(error)")
        isPictureInPictureActive = false
    }
}

