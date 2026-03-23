//
//  VoiceEntryPointPixelTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Testing
@testable import Core

@available(iOS 16, *)
@Suite("Voice Entry Point Pixels", .timeLimit(.minutes(1)))
struct VoiceEntryPointPixelTests {

    @Test("voiceEntryPointTapped pixel has correct name")
    func voiceEntryPointTappedName() {
        let pixel = Pixel.Event.voiceEntryPointTapped
        #expect(pixel.name == "m_aichat_voice_entry_point_tapped")
    }

    @Test("voiceSessionStarted pixel has correct name")
    func voiceSessionStartedName() {
        let pixel = Pixel.Event.voiceSessionStarted
        #expect(pixel.name == "m_aichat_voice_session_started")
    }

    @Test("VoiceEntryPointSource has correct raw values")
    func sourceRawValues() {
        #expect(VoiceEntryPointSource.ntp.rawValue == "ntp")
        #expect(VoiceEntryPointSource.toolbar.rawValue == "toolbar")
        #expect(VoiceEntryPointSource.addressBar.rawValue == "address_bar")
        #expect(VoiceEntryPointSource.controlCenter.rawValue == "control_center")
        #expect(VoiceEntryPointSource.widget.rawValue == "widget")
        #expect(VoiceEntryPointSource.siri.rawValue == "siri")
    }
}
