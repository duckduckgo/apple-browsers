//
//  ActiveRemoteMessageModel+NewTabPage.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation
import NewTabPage
import RemoteMessaging
import BrowserServicesKit

extension ActiveRemoteMessageModel: NewTabPageActiveRemoteMessageProviding {
    var newTabPageRemoteMessagePublisher: AnyPublisher<RemoteMessageModel?, Never> {
        $newTabPageRemoteMessage
            .dropFirst()
            .eraseToAnyPublisher()
    }

    func isMessageSupported(_ message: RemoteMessageModel) -> Bool {
        return message.content?.isSupported == true
    }

    func handleAction(_ action: RemoteAction?, andDismissUsing button: RemoteMessageButton) async {
        if let action {
            await handleAction(action)
        }
        await dismissRemoteMessage(with: .init(button))
    }

    private func handleAction(_ remoteAction: RemoteAction) async {
        switch remoteAction {
        case .url(let value), .share(let value, _):
            if let url = URL.makeURL(from: value) {
                await openURLHandler(url)
            }
        case .survey(let value):
            let refreshedURL = refreshLastSearchState(in: value)
            if let url = URL.makeURL(from: refreshedURL) {
                await openURLHandler(url)
            }
        case .appStore:
            await openURLHandler(.appStore)
        case .navigation(let value):
            switch value {
            case .feedback:
                await navigateToFeedbackHandler()
            default: break
            }
        default:
            break
        }
    }

    /// If `last_search_state` is present, refresh before opening URL
    private func refreshLastSearchState(in urlString: String) -> String {
        let lastSearchDate = AutofillUsageStore(standardUserDefaults: .standard, appGroupUserDefaults: nil).searchDauDate
        return DefaultRemoteMessagingSurveyURLBuilder.refreshLastSearchState(in: urlString, lastSearchDate: lastSearchDate)
    }
}

extension RemoteMessageViewModel.ButtonAction {

    init(_ button: RemoteMessageButton) {
        switch button {
        case .close:
            self = .close
        case .action:
            self = .action
        case .primaryAction:
            self = .primaryAction
        case .secondaryAction:
            self = .secondaryAction
        }
    }
}
