//
//  MainViewController+AIChatHistoryViewModelDelegate.swift
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

import UIKit
import AIChat

extension MainViewController: AIChatHistoryViewModelDelegate {

    func viewModelDidRequestOpenNewChat() {
        dismiss(animated: true) { [weak self] in
            self?.openAIChat()
        }
    }

    func viewModelDidRequestOpenChat(chatId: String) {
        let url = aiChatSettings.aiChatURL.withChatID(chatId)
        dismiss(animated: true) { [weak self] in
            self?.onChatHistorySelected(url: url)
        }
    }

    func viewModelDidRequestChatProtection() {
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if let tab = self.currentTab, tab.isAITab {
                tab.submitOpenChatProtectionAction()
            } else {
                let url = AIChatURLParameters.chatProtectionURL(from: self.aiChatSettings.aiChatURL)
                self.loadUrlRespectingAIBoundary(url)
            }
        }
    }

    func viewModelDidExportChat(filename: String) {
        presentChatDownloadFinishedToast(DownloadActionMessageViewHelper.makeDownloadFinishedMessage(forFilename: filename))
    }

    func viewModelDidExportChats(count: Int) {
        presentChatDownloadFinishedToast(NSAttributedString(string: UserText.aiChatHistoryDownloadCompleteMessage(count: count)))
    }

    func viewModelDidFailExport() {
        ActionMessageView.present(
            message: UserText.aiChatHistoryDownloadFailedMessage,
            presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom)
        )
    }

    private func presentChatDownloadFinishedToast(_ message: NSAttributedString) {
        ActionMessageView.present(
            message: message,
            numberOfLines: 2,
            actionTitle: UserText.actionGenericShow,
            presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom),
            onAction: { [weak self] in
                self?.dismiss(animated: true) { self?.segueToDownloads() }
            }
        )
    }
}
