//
//  MockPictureInPictureController.swift
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

import AVFoundation
import Combine
@testable import DuckDuckGo

final class MockPictureInPictureController: PictureInPictureControlling {
    private let subject = PassthroughSubject<PictureInPictureEvent, Never>()

    private(set) var didCallSetupPictureInPicture: Bool = false
    private(set) var capturedAVPlayerLayer: AVPlayerLayer?
    private(set) var didCallStopPictureInPicture: Bool = false

    var pictureInPictureEventPublisher: AnyPublisher<PictureInPictureEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    func setupPictureInPicture(playerLayer: AVPlayerLayer) {
        didCallSetupPictureInPicture = true
        capturedAVPlayerLayer = playerLayer
    }

    func stopPictureInPicture() {
        didCallStopPictureInPicture = true
    }

    // MARK: - Helper
    func send(_ event: PictureInPictureEvent) {
        subject.send(event)
    }
}
