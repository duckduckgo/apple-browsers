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

/// A type that controls the Picture in Picture functionality.
protocol PictureInPictureControlling {
    /// A publisher that emits Picture in Picture playback events.
    var pictureInPictureEventPublisher: AnyPublisher<PictureInPictureEvent, Never> { get }

    /// Sets up the Picture in Picture functionality for the specified player layer.
    ///
    /// This method configures the necessary components to enable Picture-in-Picture mode
    /// for video content. It should be called after the player and player layer are
    /// properly configured.
    ///
    /// - Parameter playerLayer: The `AVPlayerLayer` instance that contains the video
    ///   content to be displayed in Picture in Picture mode. This layer must be
    ///   associated with an `AVPlayer` that has loaded media content.
    func setupPictureInPicture(playerLayer: AVPlayerLayer)

    /// Programmatically stops the current Picture in Picture session.
    func stopPictureInPicture()
}

final class PictureInPictureController: NSObject, ObservableObject {
    private let subject = PassthroughSubject<PictureInPictureEvent, Never>()

    private let configuration: PictureInPictureConfiguration
    private let factory: PictureInPictureControllerFactory
    private var controller: AVPictureInPictureController?
    private var pictureInPictureCancellable: AnyCancellable?

#if DEBUG
    var isAVPictureInPictureControllerInitialised: Bool {
        controller != nil
    }
#endif

    init(configuration: PictureInPictureConfiguration = .init(), factory: PictureInPictureControllerFactory = AVPictureInPictureControllerFactory()) {
        self.configuration = configuration
        self.factory = factory
        super.init()
    }
}

// MARK: - PictureInPictureControlling

extension PictureInPictureController: PictureInPictureControlling {

    var pictureInPictureEventPublisher: AnyPublisher<PictureInPictureEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    func setupPictureInPicture(playerLayer: AVPlayerLayer) {
        guard let controller = factory.makePictureInPictureController(playerLayer: playerLayer) else { return }
        Logger.videoPlayer.debug("[Video Player] - PictureInPictureController initialised")
        controller.canStartPictureInPictureAutomaticallyFromInline = configuration.canStartPictureInPictureAutomaticallyFromInline
        controller.requiresLinearPlayback = configuration.requiresLinearPlayback
        controller.delegate = self
        self.controller = controller
    }

    func stopPictureInPicture() {
        Logger.videoPlayer.debug("[Video Player] - Stop Picture In Picture")
        controller?.stopPictureInPicture()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PictureInPictureController: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.videoPlayer.debug("[Video Player] - Will Start Picture in Picture")
        subject.send(.willStartPictureInPicture)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.videoPlayer.debug("[Video Player] - Picture in Picture Started")
        subject.send(.didStartPictureInPicture)
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.videoPlayer.debug("[Video Player] - Will Stop Picture in Picture")
        subject.send(.willStopPictureInPicture)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Logger.videoPlayer.debug("[Video Player] - Picture in Picture Stopped")
        subject.send(.didStopPictureInPicture)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        Logger.videoPlayer.debug("[Video Player] - Picture in Picture Failed: \(error)")
        subject.send(.failedToStartPictureInPicture)
    }
}
