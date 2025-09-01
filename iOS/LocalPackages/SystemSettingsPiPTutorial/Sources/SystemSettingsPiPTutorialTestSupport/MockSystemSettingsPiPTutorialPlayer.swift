//
//  MockSystemSettingsPiPTutorialPlayer.swift
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
@testable import SystemSettingsPiPTutorial

package final class MockSystemSettingsPiPTutorialPlayer: SystemSettingsPiPTutorialPlayer {
    package private(set) var didCallLoadURL = false
    package private(set) var capturedURL: URL?
    package private(set) var didCallPlay = false
    package private(set) var didCallStop = false

    package var isPiPSupported = true
    package var onPlay: (() -> Void)?

    private let subject = PassthroughSubject<AVPlayerItem.Status, Never>()
    package var playerItemStatusPublisher: AnyPublisher<AVPlayerItem.Status, Never> { subject.eraseToAnyPublisher() }

    package init() {}

    package var currentItemError: Error?

    package var currentItemURL: URL?

    package func isPictureInPictureSupported() -> Bool {
        isPiPSupported
    }
    
    package func load(url: URL) {
        didCallLoadURL = true
        capturedURL = url
    }
    
    package func play() {
        didCallPlay = true
        onPlay?()
    }
    
    package func stop() {
        didCallStop = true
    }

    package func send(event: AVPlayerItem.Status) {
        subject.send(event)
    }

}
