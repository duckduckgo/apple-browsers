//
//  VoiceSessionStateManager.swift
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

/// Observes `aiChatVoiceSessionStarted` / `aiChatVoiceSessionEnded` notifications
/// posted by the AI Chat user script handler. Used by the idle-return escape hatch
/// to skip NTP creation while voice is in progress.
protocol VoiceSessionStateProviding: AnyObject {
    var isVoiceSessionActive: Bool { get }
}

final class VoiceSessionStateManager: VoiceSessionStateProviding {
    private(set) var isVoiceSessionActive: Bool = false

    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        notificationCenter.addObserver(self, selector: #selector(voiceSessionStarted), name: .aiChatVoiceSessionStarted, object: nil)
        notificationCenter.addObserver(self, selector: #selector(voiceSessionEnded), name: .aiChatVoiceSessionEnded, object: nil)
    }

    @objc private func voiceSessionStarted() {
        isVoiceSessionActive = true
    }

    @objc private func voiceSessionEnded() {
        isVoiceSessionActive = false
    }
}
