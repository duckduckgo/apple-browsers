//
//  AudioSessionManager.swift
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

enum AudioSessionPlaybackOption {
    /// An option that indicates whether audio from this session mixes with audio from active sessions in other audio apps
    case mixWithOthers
    /// An option that reduces the volume of other audio sessions while audio from this session plays
    case duckOthers
}

protocol AudioSessionManaging: AnyObject {
    /// Sets  the current Audio Session to playback and activates it. The default behaviour of the session is to mix with audio from active sessions in other audio apps.
    ///
    /// Calling this method when a higher-priority audio session is in progress (E.g. Phone Call) will do nothing.
    func setPlaybackSessionActive(option: AudioSessionPlaybackOption)
    /// Deactivates the current audio session.
    ///
    /// Call this method when AVPlayer has not an active AVPlayerItem currentItem. Failing in do so will  cause a failure to deactivate the Audio Session.
    func setPlaybackSessionInactive()
}

extension AudioSessionManaging {

    func setPlaybackSessionActive() {
        setPlaybackSessionActive(option: .mixWithOthers)
    }

}

final class AudioSessionManager {

    private let audioSession: AudioSession

    init(audioSession: AudioSession = AVAudioSession.sharedInstance()) {
        self.audioSession = audioSession
    }

}

// MARK: - AudioSessionManagerInterface

extension AudioSessionManager: AudioSessionManaging {

    public func setPlaybackSessionActive(option: AudioSessionPlaybackOption) {
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: AVAudioSession.CategoryOptions(option))
            try audioSession.setActive(true)
            Logger.videoPlayer.debug("[Video Player] - Audio session activated successfully.")
        } catch {
            Logger.videoPlayer.debug("[Video Player] - Failed to activate audio session. Reason: \(error.localizedDescription)")
        }
    }

    public func setPlaybackSessionInactive() {
        do {
            // This would throw an error if the session is deactivated while AVPlayer has a current AVPlayerItem.
            try audioSession.setActive(false)
            Logger.videoPlayer.debug("[Video Player] - Audio session deactivated successfully.")
        } catch {
            Logger.videoPlayer.debug("[Video Player] - Failed to deactivate audio session. Reason: \(error.localizedDescription)")
        }
    }

}

// MARK: - Helpers

extension AVAudioSession.CategoryOptions {

    init(_ playbackOption: AudioSessionPlaybackOption) {
        switch playbackOption {
        case .mixWithOthers:
            self = .mixWithOthers
        case .duckOthers:
            self = .duckOthers
        }
    }

}
