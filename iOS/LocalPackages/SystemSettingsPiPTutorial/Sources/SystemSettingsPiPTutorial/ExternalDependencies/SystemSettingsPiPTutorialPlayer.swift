//
//  SystemSettingsPiPTutorialPlayer.swift
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

// A type that can play PiP tutorial content.
public protocol SystemSettingsPiPTutorialPlayer {
    /// A Combine publisher that emits the current status of the player item.
    ///
    /// Subscribers can observe this publisher to react to changes in the player's status, such as when content is ready to play or fails to load.
    var playerItemStatusPublisher: AnyPublisher<AVPlayerItem.Status, Never> { get }

    /// The error that caused the player item to fail.
    var currentItemError: Error? { get }

    /// The URL to the asset’s media.
    var currentItemURL: URL? { get }

    // Determines whether PiP playback is supported on the current device.
    ///
    /// - Returns: `true` if PiP is supported; `false` otherwise.
    func isPictureInPictureSupported() -> Bool

    /// Loads video content from the specified URL for playback.
    ///
    /// - Parameter url: The URL of the video content to load
    func load(url: URL)

    /// Begins playback of the currently loaded content.
    func play()

    /// Stops playback and releases any loaded content.
    func stop()
}
