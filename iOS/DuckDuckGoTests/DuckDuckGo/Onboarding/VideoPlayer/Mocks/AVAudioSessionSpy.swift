//
//  AVAudioSessionSpy.swift
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
@testable import DuckDuckGo

final class AVAudioSessionSpy: AudioSession {
    private(set) var category: AVAudioSession.Category?
    private(set) var mode: AVAudioSession.Mode?
    private(set) var categoryOptions: AVAudioSession.CategoryOptions = []

    private(set) var active: Bool = false
    private(set) var activeOptions: AVAudioSession.SetActiveOptions = []

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        self.category = category
        self.mode = mode
        categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        self.active = active
        activeOptions = options
    }
}
