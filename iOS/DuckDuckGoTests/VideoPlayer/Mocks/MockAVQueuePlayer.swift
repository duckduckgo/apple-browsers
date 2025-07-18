//
//  MockAVQueuePlayer.swift
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

final class MockAVQueuePlayer: AVQueuePlayer {
    private(set) var didCallPlay = false
    private(set) var didCallPause = false
    private(set) var didCallReplaceCurrentItem = false
    private(set) var capturedCurrentItem: AVPlayerItem?

    override func replaceCurrentItem(with item: AVPlayerItem?) {
        didCallReplaceCurrentItem = true
        self.capturedCurrentItem = item
    }

    override func play() {
        didCallPlay = true
    }

    override func pause() {
        didCallPause = true
    }
}
