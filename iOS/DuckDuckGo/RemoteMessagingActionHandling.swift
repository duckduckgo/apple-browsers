//
//  RemoteMessagingActionHandling.swift
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

import Foundation
import Core
import RemoteMessaging
import class UIKit.UIApplication

struct PresentationContext {
    enum Style {
        /// Dismiss any visible modals and present the screen
        case dismissModalsAndPresentFromRoot
        /// Present from the current presented screen.
        case withinCurrentContext
    }

    let presenter: RemoteMessagingPresenter
    let presentationStyle: Style
}

protocol RemoteMessagingPresenter {
    func presentActivitySheet(value: String, title: String?) async
    func presentEmbeddedWebView(url: URL) async
}

protocol RemoteMessagingActionHandling {
    func handleAction(_ remoteAction: RemoteAction, context: PresentationContext) async
}

final class RemoteMessagingActionHandler: RemoteMessagingActionHandling {
    private let lastSearchStateRefresher: RemoteMessagingLastSearchStateRefresher
    private let urlOpener: URLOpener
    private let browserTabUrlOpener: (_ urlPath: String) -> Void

    var messageNavigator: MessageNavigator?

    init(
        lastSearchStateRefresher: RemoteMessagingLastSearchStateRefresher = RemoteMessagingSurveyLastSearchStateRefresher(),
        urlOpener: URLOpener = UIApplication.shared,
        browserTabUrlOpener: @escaping (_ urlPath: String) -> Void = LaunchTabNotification.postLaunchTabNotification
    ) {
        self.lastSearchStateRefresher = lastSearchStateRefresher
        self.urlOpener = urlOpener
        self.browserTabUrlOpener = browserTabUrlOpener
    }

    @MainActor
    func handleAction(_ remoteAction: RemoteAction, context: PresentationContext) async {
        switch remoteAction {
        case .share(let value, let title):
            await context.presenter.presentActivitySheet(value: value, title: title)
        case .url(let value):
            browserTabUrlOpener(value)
        case .urlInContext(let value):
            guard let url = URL.webUrl(from: value) else { return }
            await context.presenter.presentEmbeddedWebView(url: url)
        case .appStore:
            let url = URL.appStore
            if urlOpener.canOpenURL(url) {
                urlOpener.open(url)
            }
        case .survey(let value):
            let refreshedURL = lastSearchStateRefresher.refreshLastSearchState(forURLPath: value)
            browserTabUrlOpener(refreshedURL)
        case .navigation(let target):
            messageNavigator?.navigateTo(target, presentationStyle: context.presentationStyle)
        case .dismiss:
            break
        }
    }
}
