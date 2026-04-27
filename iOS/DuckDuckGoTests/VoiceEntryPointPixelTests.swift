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
@testable import DuckDuckGo

@Suite("Voice Entry Point Pixels")
struct VoiceEntryPointPixelTests {

    @available(iOS 16, *)
    @Test("voiceEntryPointTapped pixel has correct name", .timeLimit(.minutes(1)))
    func voiceEntryPointTappedName() {
        let pixel = Pixel.Event.voiceEntryPointTapped
        #expect(pixel.name == "m_aichat_voice_entry_point_tapped")
    }

    @available(iOS 16, *)
    @Test("voiceSessionStarted pixel has correct name", .timeLimit(.minutes(1)))
    func voiceSessionStartedName() {
        let pixel = Pixel.Event.voiceSessionStarted
        #expect(pixel.name == "m_aichat_voice_session_started")
    }

    @available(iOS 16, *)
    @Test("VoiceEntryPointSource has correct raw values", .timeLimit(.minutes(1)))
    func sourceRawValues() {
        #expect(VoiceEntryPointSource.ntp.rawValue == "ntp")
        #expect(VoiceEntryPointSource.toolbar.rawValue == "toolbar")
        #expect(VoiceEntryPointSource.addressBar.rawValue == "address_bar")
        #expect(VoiceEntryPointSource.controlCenter.rawValue == "widget.controlcenter")
        #expect(VoiceEntryPointSource.lockscreenComplication.rawValue == "widget.lockscreen.complication")
        #expect(VoiceEntryPointSource.quickActions.rawValue == "widget.quickactions")
        #expect(VoiceEntryPointSource.siri.rawValue == "siri")
    }
}
