//
//  AIChatHistoryInstrumentation.swift
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

import Core

/// Where the chat history screen was opened from. Sent as the `source` parameter on the
/// screen-shown impression pixel.
enum AIChatHistorySource: String {
    case browserMenu = "browser_menu"
    case addressBar = "address_bar"
    case contextualChat = "contextual_chat"
}

protocol AIChatHistoryInstrumentation {
    func screenShown(source: AIChatHistorySource)
    func chatOpened()
    func chatDeleted()
    func emptyCTATapped()
    func searchActivated()
    func fireAllTapped()
    func fireAllConfirmed()
    func pinAdded()
    func pinRemoved()
    func downloadStarted()
    func downloadSucceeded()
    func selectionDeleteConfirmed()
    func selectionDownloadStarted()
    func chatProtectionTapped()
    func editModeEntered()
    func newChatTapped()
    func loadFailed(error: Error)
    func pinToggleFailed(error: Error)
    func downloadFailed(error: Error)
}

final class DefaultAIChatHistoryInstrumentation: AIChatHistoryInstrumentation {

    private let dailyPixelFiring: DailyPixelFiring.Type

    init(dailyPixelFiring: DailyPixelFiring.Type = DailyPixel.self) {
        self.dailyPixelFiring = dailyPixelFiring
    }

    func screenShown(source: AIChatHistorySource) {
        dailyPixelFiring.fireDailyAndCount(.aiChatHistoryScreenShown,
                                           error: nil,
                                           withAdditionalParameters: [PixelParameters.source: source.rawValue])
    }

    func chatOpened() {
        fire(.aiChatHistoryChatOpened)
    }

    func chatDeleted() {
        fire(.aiChatHistoryChatDeleted)
    }

    func emptyCTATapped() {
        fire(.aiChatHistoryEmptyCTATapped)
    }

    func searchActivated() {
        fire(.aiChatHistorySearchActivated)
    }

    func fireAllTapped() {
        fire(.aiChatHistoryFireAllTapped)
    }

    func fireAllConfirmed() {
        fire(.aiChatHistoryFireAllConfirmed)
    }

    func pinAdded() {
        fire(.aiChatHistoryPinAdded)
    }

    func pinRemoved() {
        fire(.aiChatHistoryPinRemoved)
    }

    func downloadStarted() {
        fire(.aiChatHistoryDownloadStarted)
    }

    func downloadSucceeded() {
        fire(.aiChatHistoryDownloadSuccessful)
    }

    func selectionDeleteConfirmed() {
        fire(.aiChatHistorySelectionDeleteConfirmed)
    }

    func selectionDownloadStarted() {
        fire(.aiChatHistorySelectionDownloadStarted)
    }

    func chatProtectionTapped() {
        fire(.aiChatHistoryChatProtectionTapped)
    }

    func editModeEntered() {
        fire(.aiChatHistoryEditModeEntered)
    }

    func newChatTapped() {
        fire(.aiChatHistoryNewChatTapped)
    }

    func loadFailed(error: Error) {
        fire(.aiChatHistoryLoadFailed, error: error)
    }

    func pinToggleFailed(error: Error) {
        fire(.aiChatHistoryPinToggleFailed, error: error)
    }

    func downloadFailed(error: Error) {
        fire(.aiChatHistoryDownloadFailed, error: error)
    }

    private func fire(_ pixel: Pixel.Event, error: Error? = nil) {
        dailyPixelFiring.fireDailyAndCount(pixel, error: error, withAdditionalParameters: [:])
    }
}
