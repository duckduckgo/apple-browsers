//
//  NewChatHintsUsage.swift
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
import Persistence
import PixelKit

/// How many new chats in a row the user started typing in without tapping a hint. Hints stop once it reaches
/// `hideAfterIgnoredChats`. The count persists rather than a "hidden" flag, so raising the limit brings them back.
struct NewChatHintsCapStore {
    static let hideAfterIgnoredChats = 5
    static let ignoredChatsKey = "aichat.new-chat-hints.ignored-chats"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var ignoredChats: Int {
        max(0, (try? keyValueStore.object(forKey: Self.ignoredChatsKey) as? Int) ?? 0)
    }

    var isReached: Bool { ignoredChats >= Self.hideAfterIgnoredChats }

    /// Returns the new count.
    func recordIgnoredChat() -> Int {
        let count = ignoredChats + 1
        try? keyValueStore.set(count, forKey: Self.ignoredChatsKey)
        return count
    }

    func reset() {
        try? keyValueStore.removeObject(forKey: Self.ignoredChatsKey)
    }
}

/// Follows each tab's new chat from the moment it shows to its first prompt, to fire the hint pixels once each
/// and to count the chats where the hints were ignored. Everything runs on the main actor, so the count's
/// read-then-write never interleaves.
@MainActor
final class NewChatHintsUsage {

    private struct NewChat {
        let isFireTab: Bool
        /// Hints showed at some point in this chat. Stays true if a promo covers them later.
        var hintsShown = false
        /// Hints showed and nothing has covered them since, so a prompt now means they were ignored.
        var isDisplayed = false
        /// The last hint tapped. Any tap means the hints weren't ignored.
        var tappedHint: NewChatHint?
        /// Its first prompt went out. Kept until the tab leaves the chat: the input still looks like a blank new
        /// chat for a moment after the submit, which must not count as another one.
        var isPrompted = false
    }

    private let capStore: NewChatHintsCapStore
    private let pixelFiring: PixelFiring?
    private let isFeatureEnabled: () -> Bool
    private var newChats: [TabUID: NewChat] = [:]

    init(capStore: NewChatHintsCapStore = NewChatHintsCapStore(),
         pixelFiring: PixelFiring? = PixelKit.shared,
         isFeatureEnabled: @escaping () -> Bool) {
        self.capStore = capStore
        self.pixelFiring = pixelFiring
        self.isFeatureEnabled = isFeatureEnabled
    }

    var isCapReached: Bool { capStore.isReached }

    /// A tab is on a guaranteed new chat. Counts it once, until it leaves that chat. Returns whether this started it.
    @discardableResult
    func newChatShown(tab: TabUID, isFireTab: Bool) -> Bool {
        guard newChats[tab] == nil else { return false }
        newChats[tab] = NewChat(isFireTab: isFireTab)
        fire(.newChatShown(isFeatureEnabled: isFeatureEnabled()))
        return true
    }

    /// `hints` are on screen, in this order. Fires once per new chat.
    func hintsShown(_ hints: [NewChatHint], tab: TabUID) {
        guard !hints.isEmpty, var chat = newChats[tab], !chat.isPrompted else { return }
        if !chat.hintsShown {
            fire(.hintsShown(hints))
        }
        chat.hintsShown = true
        chat.isDisplayed = !chat.isFireTab
        newChats[tab] = chat
    }

    /// A promo covers the hints, so a prompt sent now doesn't mean they were ignored.
    func promoShown(tab: TabUID) {
        newChats[tab]?.isDisplayed = false
    }

    /// `position` is 1-based.
    func hintTapped(_ hint: NewChatHint, position: Int, tab: TabUID) {
        fire(.hintTapped(hint, position: position))
        guard newChats[tab]?.isPrompted == false else { return }
        newChats[tab]?.tappedHint = hint
    }

    /// The file picker the documents hint opened closed without a file chosen.
    func filePickerCancelled() {
        fire(.filePickerCancelled)
    }

    /// The tab moved to a chat that isn't new, or off Duck.ai, without sending from this one.
    func leftNewChat(tab: TabUID) {
        newChats[tab] = nil
    }

    /// A prompt went out from `tab`. Only the first prompt of a counted new chat reports or moves the count.
    func promptSubmitted(tab: TabUID, isNewChat: Bool, prompt: NewChatHintsPixel.FirstPrompt) {
        guard var chat = newChats[tab], !chat.isPrompted else { return }
        guard isNewChat else {
            newChats[tab] = nil
            return
        }
        chat.isPrompted = true
        newChats[tab] = chat
        fire(.firstPromptSent(isFeatureEnabled: isFeatureEnabled(),
                              hintsShown: chat.hintsShown,
                              tappedHint: chat.tappedHint,
                              prompt: prompt))
        // With the flag off nothing is offered, so nothing was ignored or used: the cap only counts while it's on.
        guard !chat.isFireTab, isFeatureEnabled() else { return }
        if chat.tappedHint != nil {
            capStore.reset()
        } else if chat.isDisplayed, capStore.recordIgnoredChat() == NewChatHintsCapStore.hideAfterIgnoredChats {
            fire(.capReached)
        }
    }

    private func fire(_ pixel: NewChatHintsPixel) {
        pixelFiring?.fire(pixel, frequency: pixel.frequency)
    }
}
