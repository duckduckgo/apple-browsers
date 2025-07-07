//
//  AudioSession.swift
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

// Protocol to mock AVAudioSession
protocol AudioSession: AnyObject {
    /// Sets the audio session’s category, mode, and options.
    /// - Parameters:
    ///   - category: The category to apply to the audio session. See [AVAudioSession.Category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct) for supported category values
    ///   - mode: The audio session mode to apply to the audio session. For a list of values, see [AVAudioSession.Mode](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct).
    ///   - options: A mask of additional options for handling audio. For a list of constants, see [AVAudioSession.CategoryOptions](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct).
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    
    /// Activates or deactivates your app’s audio session using the specified options.
    /// - Parameters:
    ///   - active: Specify true to activate your app’s audio session, or false to deactivate it.
    ///   - options: An integer bit mask containing one or more constants from the [AVAudioSession.SetActiveOptions](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactiveoptions) enumeration
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AudioSession {

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions = []) throws {
        try setActive(active, options: options)
    }

}

extension AVAudioSession: AudioSession {}
