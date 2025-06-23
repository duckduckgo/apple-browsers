//
//  PictureInPictureControllerFactory.swift
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

protocol PictureInPictureControllerFactory {
    func makePictureInPictureController(playerLayer: AVPlayerLayer) -> AVPictureInPictureController?
}

final class AVPictureInPictureControllerFactory: PictureInPictureControllerFactory {
    private let isPictureInPictureSupported: Bool

    init(isPictureInPictureSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()) {
        self.isPictureInPictureSupported = isPictureInPictureSupported
    }

    func makePictureInPictureController(playerLayer: AVPlayerLayer) -> AVPictureInPictureController? {
        guard isPictureInPictureSupported else {
            Logger.videoPlayer.debug("[Video Player] - Picture In Picture Not Supported")
            return nil
        }

        guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
            Logger.videoPlayer.debug("[Video Player] - Could Not initialise PictureInPictureController")
            return nil
        }

        return controller
    }

}
