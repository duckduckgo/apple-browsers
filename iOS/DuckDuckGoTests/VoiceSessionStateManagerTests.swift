//
//  VoiceSessionStateManagerTests.swift
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

import Foundation
import Testing
@testable import DuckDuckGo

@Suite("VoiceSessionStateManager")
struct VoiceSessionStateManagerTests {

    @available(iOS 16, *)
    @Test("Initially voice session is not active", .timeLimit(.minutes(1)))
    func initialState() {
        let sut = VoiceSessionStateManager()
        #expect(!sut.isVoiceSessionActive)
    }

    @available(iOS 16, *)
    @Test("Voice session becomes active after voiceSessionStarted notification", .timeLimit(.minutes(1)))
    func voiceSessionStarted() {
        let notificationCenter = NotificationCenter()
        let sut = VoiceSessionStateManager(notificationCenter: notificationCenter)

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: nil)

        #expect(sut.isVoiceSessionActive)
    }

    @available(iOS 16, *)
    @Test("Voice session becomes inactive after voiceSessionEnded notification", .timeLimit(.minutes(1)))
    func voiceSessionEnded() {
        let notificationCenter = NotificationCenter()
        let sut = VoiceSessionStateManager(notificationCenter: notificationCenter)

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: nil)
        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: nil)

        #expect(!sut.isVoiceSessionActive)
    }

    @available(iOS 16, *)
    @Test("Multiple start/end cycles work correctly", .timeLimit(.minutes(1)))
    func multipleCycles() {
        let notificationCenter = NotificationCenter()
        let sut = VoiceSessionStateManager(notificationCenter: notificationCenter)

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: nil)
        #expect(sut.isVoiceSessionActive)

        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: nil)
        #expect(!sut.isVoiceSessionActive)

        notificationCenter.post(name: .aiChatVoiceSessionStarted, object: nil)
        #expect(sut.isVoiceSessionActive)
    }

    @available(iOS 16, *)
    @Test("End notification without start keeps state inactive", .timeLimit(.minutes(1)))
    func endWithoutStart() {
        let notificationCenter = NotificationCenter()
        let sut = VoiceSessionStateManager(notificationCenter: notificationCenter)

        notificationCenter.post(name: .aiChatVoiceSessionEnded, object: nil)

        #expect(!sut.isVoiceSessionActive)
    }
}
